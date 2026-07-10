/// Lightweight in-memory holder for the AI chat's per-session toggles from
/// the "Add to chat" sheet (web search, tool access). Kept as a simple
/// singleton so the sheet and the chat service share one source of truth;
/// the request builder reads these when sending a message. These wire into
/// real backend web-search / tool-calling as those land.
class AiChatPrefs {
  AiChatPrefs._();
  static final AiChatPrefs instance = AiChatPrefs._();

  /// When true, the AI may ground answers with a web search (backend runs it).
  bool webSearch = false;

  /// When true (Auto), the AI may use tools (structured queries, interactive
  /// questions) via the backend tool-calling path.
  bool toolAccess = true;
}
