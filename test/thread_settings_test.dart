import 'package:codexcli_remote/protocol/thread_settings.dart';
import 'package:codexcli_remote/protocol/turn.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TokenUsage.fromJson', () {
    test('uses `last` for context and `total` for the session sum', () {
      final u = TokenUsage.fromJson({
        'threadId': 't1',
        'turnId': 'turn1',
        'tokenUsage': {
          'total': {'totalTokens': 500000, 'inputTokens': 480000},
          'last': {
            'totalTokens': 32000,
            'inputTokens': 30000,
            'cachedInputTokens': 1000,
            'outputTokens': 2000,
          },
          'modelContextWindow': 128000,
        },
      });
      // Context reflects `last`, not the ever-growing `total`.
      expect(u.contextTokens, 32000);
      expect(u.sessionTotalTokens, 500000);
      expect(u.contextWindow, 128000);
      // used = (32000-12000) / (128000-12000) = 20000/116000 ≈ 17.2% -> 17
      expect(u.contextUsedPercent, 17);
      expect(u.contextRemainingPercent, 83);
    });

    test('a fresh thread below the baseline reads 0% used', () {
      final u = TokenUsage.fromJson({
        'tokenUsage': {
          'last': {'totalTokens': 8000},
          'total': {'totalTokens': 8000},
          'modelContextWindow': 128000,
        },
      });
      expect(u.contextUsedPercent, 0);
    });

    test('context percent stays <= 100 even when last exceeds the window', () {
      // Regression: previously used cumulative `total` and blew past 100%.
      final u = TokenUsage.fromJson({
        'tokenUsage': {
          'last': {'totalTokens': 200000},
          'total': {'totalTokens': 9000000},
          'modelContextWindow': 128000,
        },
      });
      expect(u.contextUsedPercent, 100);
      expect(u.contextFraction, 1.0);
    });

    test('falls back to a flat breakdown with no window', () {
      final u = TokenUsage.fromJson({
        'totalTokens': 10,
        'inputTokens': 6,
        'outputTokens': 4,
      });
      expect(u.contextTokens, 10);
      expect(u.sessionTotalTokens, 10);
      expect(u.contextWindow, isNull);
      expect(u.contextUsedPercent, isNull);
      expect(u.contextFraction, isNull);
    });
  });

  group('ApprovalPolicy.fromWire', () {
    test('parses bare string tags', () {
      expect(ApprovalPolicy.fromWire('on-request'), ApprovalPolicy.onRequest);
      expect(ApprovalPolicy.fromWire('untrusted'), ApprovalPolicy.untrusted);
      expect(ApprovalPolicy.fromWire('never'), ApprovalPolicy.never);
    });

    test('parses the granular object form', () {
      expect(
        ApprovalPolicy.fromWire({'type': 'granular', 'rules': []}),
        ApprovalPolicy.granular,
      );
    });

    test('returns null for unknown/absent values', () {
      expect(ApprovalPolicy.fromWire(null), isNull);
      expect(ApprovalPolicy.fromWire('bogus'), isNull);
    });
  });

  group('ThreadSettings.fromMap', () {
    test('parses thread/resume top-level shape', () {
      final s = ThreadSettings.fromMap({
        'model': 'gpt-5-codex',
        'approvalPolicy': 'on-request',
        'reasoningEffort': 'high',
        'cwd': '/home/me/proj',
        'thread': {'name': 'Fix bug'},
      });
      expect(s.model, 'gpt-5-codex');
      expect(s.approvalPolicy, ApprovalPolicy.onRequest);
      expect(s.effort, ReasoningEffort.high);
      expect(s.cwd, '/home/me/proj');
      expect(s.name, 'Fix bug');
    });

    test('reads effort from either reasoningEffort or effort key', () {
      final s = ThreadSettings.fromMap({'effort': 'low'});
      expect(s.effort, ReasoningEffort.low);
    });
  });

  group('ModelInfo.fromJson', () {
    test('parses id, display name, default flag, and supported efforts', () {
      final m = ModelInfo.fromJson({
        'id': 'gpt-5-codex',
        'model': 'gpt-5-codex',
        'displayName': 'GPT-5 Codex',
        'isDefault': true,
        'defaultReasoningEffort': 'medium',
        'supportedReasoningEfforts': [
          {'reasoningEffort': 'low', 'description': 'faster'},
          {'reasoningEffort': 'high', 'description': 'slower'},
        ],
      });
      expect(m.model, 'gpt-5-codex');
      expect(m.displayName, 'GPT-5 Codex');
      expect(m.isDefault, isTrue);
      expect(m.defaultEffort, ReasoningEffort.medium);
      expect(m.supportedEfforts, [ReasoningEffort.low, ReasoningEffort.high]);
    });
  });
}
