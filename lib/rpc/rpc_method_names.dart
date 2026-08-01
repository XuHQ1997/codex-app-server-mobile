/// Canonical JSON-RPC method names used by the codex app-server (v2 protocol).
///
/// Grouped by lifecycle / domain. Only the subset this client actually sends or
/// handles is listed; unknown inbound methods are ignored by the notification
/// and server-request routers.
class RpcMethods {
  RpcMethods._();

  // Lifecycle
  static const initialize = 'initialize';
  static const initialized = 'initialized';

  // Threads
  static const threadStart = 'thread/start';
  static const threadResume = 'thread/resume';
  static const threadList = 'thread/list';
  static const threadRead = 'thread/read';
  static const threadArchive = 'thread/archive';
  static const threadDelete = 'thread/delete';
  static const threadCompactStart = 'thread/compact/start';
  static const threadGoalSet = 'thread/goal/set';
  static const threadGoalClear = 'thread/goal/clear';
  static const threadSettingsUpdate = 'thread/settings/update';

  // Turns
  static const turnStart = 'turn/start';
  static const turnSteer = 'turn/steer';
  static const turnInterrupt = 'turn/interrupt';

  // Models
  static const modelList = 'model/list';

  // Filesystem (browse the app-server host's working tree)
  static const fsReadDirectory = 'fs/readDirectory';
  static const fsReadFile = 'fs/readFile';
  static const fsGetMetadata = 'fs/getMetadata';

  // ---- Inbound notification methods ----
  static const nTurnStarted = 'turn/started';
  static const nTurnCompleted = 'turn/completed';
  static const nTurnPlanUpdated = 'turn/plan/updated';
  static const nItemStarted = 'item/started';
  static const nItemCompleted = 'item/completed';
  static const nItemAgentMessageDelta = 'item/agentMessage/delta';
  static const nItemReasoningSummaryTextDelta =
      'item/reasoning/summaryTextDelta';
  static const nItemReasoningSummaryPartAdded =
      'item/reasoning/summaryPartAdded';
  static const nItemReasoningTextDelta = 'item/reasoning/textDelta';
  static const nItemCommandOutputDelta = 'item/commandExecution/outputDelta';
  static const nItemFileChangePatchUpdated = 'item/fileChange/patchUpdated';
  static const nTokenUsageUpdated = 'thread/tokenUsage/updated';
  static const nThreadSettingsUpdated = 'thread/settings/updated';
  static const nError = 'error';

  // ---- Inbound server->client REQUEST methods (require a response) ----
  static const rCommandExecutionApproval =
      'item/commandExecution/requestApproval';
  static const rFileChangeApproval = 'item/fileChange/requestApproval';
  static const rPermissionsApproval = 'item/permissions/requestApproval';
  static const rToolRequestUserInput = 'item/tool/requestUserInput';
}
