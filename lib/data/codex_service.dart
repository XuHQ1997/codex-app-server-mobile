import 'dart:convert';

import '../protocol/fs_entry.dart';
import '../protocol/input/user_input.dart';
import '../protocol/thread.dart';
import '../protocol/thread_settings.dart';
import '../rpc/rpc_client.dart';
import '../rpc/rpc_method_names.dart';

/// Thin typed facade over [RpcClient] for the codex app-server methods this
/// app uses. Repositories and controllers call these instead of raw method
/// strings.
class CodexService {
  CodexService(this.client);

  final RpcClient client;

  // ---- Threads ----

  Future<ThreadListPage> listThreads({
    String? cursor,
    int limit = 30,
    bool archived = false,
    String? searchTerm,
  }) async {
    final result = await client.callObject(
      RpcMethods.threadList,
      params: {
        'cursor': ?cursor,
        'limit': limit,
        'archived': archived,
        if (searchTerm != null && searchTerm.isNotEmpty) 'searchTerm': searchTerm,
      },
    );
    return ThreadListPage.fromJson(result);
  }

  Future<Map<String, dynamic>> startThread({String? cwd, String? model}) {
    return client.callObject(
      RpcMethods.threadStart,
      params: {
        'cwd': ?cwd,
        'model': ?model,
      },
    );
  }

  Future<Map<String, dynamic>> resumeThread(String threadId) {
    return client.callObject(
      RpcMethods.threadResume,
      params: {'threadId': threadId},
    );
  }

  Future<Map<String, dynamic>> readThread(
    String threadId, {
    bool includeTurns = true,
  }) {
    return client.callObject(
      RpcMethods.threadRead,
      params: {'threadId': threadId, 'includeTurns': includeTurns},
    );
  }

  Future<void> archiveThread(String threadId) =>
      client.call(RpcMethods.threadArchive, params: {'threadId': threadId});

  Future<void> deleteThread(String threadId) =>
      client.call(RpcMethods.threadDelete, params: {'threadId': threadId});

  Future<void> compactThread(String threadId) => client.call(
    RpcMethods.threadCompactStart,
    params: {'threadId': threadId},
  );

  /// Sets or updates the thread goal (objective for a long-running task).
  /// Returns the resulting goal object.
  Future<Map<String, dynamic>> setGoal(
    String threadId, {
    String? objective,
    String? status,
  }) {
    return client.callObject(
      RpcMethods.threadGoalSet,
      params: {
        'threadId': threadId,
        'objective': ?objective,
        'status': ?status,
      },
    );
  }

  /// Sets [objective] as the persistent goal and starts a turn with the same
  /// text. A goal by itself only updates thread metadata; the turn is what
  /// records the user's instruction in history and wakes the agent to work.
  Future<Map<String, dynamic>> setGoalAndStart(
    String threadId,
    String objective,
  ) async {
    await setGoal(threadId, objective: objective);
    return startTurn(threadId, [TextInput(objective)]);
  }

  /// Clears the thread goal.
  Future<void> clearGoal(String threadId) => client.call(
    RpcMethods.threadGoalClear,
    params: {'threadId': threadId},
  );

  /// Updates live thread settings (model / approval policy / reasoning effort)
  /// without starting a new turn. Backed by the experimental
  /// `thread/settings/update` method; callers should handle a method-not-found
  /// error as "server too old to support this".
  Future<void> updateThreadSettings(
    String threadId, {
    String? model,
    ApprovalPolicy? approvalPolicy,
    ReasoningEffort? effort,
  }) {
    return client.call(
      RpcMethods.threadSettingsUpdate,
      params: {
        'threadId': threadId,
        'model': ?model,
        'approvalPolicy': ?approvalPolicy?.wire,
        'effort': ?effort?.wire,
      },
    );
  }

  /// Lists available models for the model picker.
  Future<List<ModelInfo>> listModels({bool includeHidden = false}) async {
    final result = await client.callObject(
      RpcMethods.modelList,
      params: {'includeHidden': includeHidden},
    );
    final data = result['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(ModelInfo.fromJson)
        .toList();
  }

  // ---- Turns ----

  Future<Map<String, dynamic>> startTurn(
    String threadId,
    List<UserInput> input, {
    String? clientUserMessageId,
  }) {
    return client.callObject(
      RpcMethods.turnStart,
      params: {
        'threadId': threadId,
        'input': input.map((i) => i.toJson()).toList(),
        'clientUserMessageId': ?clientUserMessageId,
      },
    );
  }

  Future<Map<String, dynamic>> steerTurn(
    String threadId,
    List<UserInput> input,
  ) {
    return client.callObject(
      RpcMethods.turnSteer,
      params: {
        'threadId': threadId,
        'input': input.map((i) => i.toJson()).toList(),
      },
    );
  }

  Future<void> interruptTurn(String threadId, String turnId) => client.call(
    RpcMethods.turnInterrupt,
    params: {'threadId': threadId, 'turnId': turnId},
  );

  // ---- Filesystem (browse the app-server host) ----

  /// Lists the direct children of an absolute directory [path] on the host.
  /// Entries come back unsorted; callers sort for display.
  Future<List<FsEntry>> readDirectory(String path) async {
    final result = await client.callObject(
      RpcMethods.fsReadDirectory,
      params: {'path': path},
    );
    final entries = result['entries'];
    if (entries is! List) return const [];
    return entries
        .whereType<Map<String, dynamic>>()
        .map(FsEntry.fromJson)
        .toList();
  }

  /// Reads an absolute file [path], returning its raw bytes (base64-decoded
  /// on the wire by the caller-facing return type).
  Future<List<int>> readFile(String path) async {
    final result = await client.callObject(
      RpcMethods.fsReadFile,
      params: {'path': path},
    );
    final b64 = result['dataBase64'] as String? ?? '';
    return base64.decode(b64);
  }

  /// Returns metadata (type + timestamps) for an absolute [path].
  Future<FsMetadata> getMetadata(String path) async {
    final result = await client.callObject(
      RpcMethods.fsGetMetadata,
      params: {'path': path},
    );
    return FsMetadata.fromJson(result);
  }
}
