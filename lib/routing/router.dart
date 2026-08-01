import 'package:go_router/go_router.dart';

import '../ui/setup/setup_screen.dart';
import '../ui/threads/thread_list_screen.dart';
import '../ui/chat/chat_screen.dart';
import '../ui/common/frame_inspector_screen.dart';

/// App navigation: setup -> threads -> chat, plus the debug frame inspector.
final appRouter = GoRouter(
  initialLocation: '/setup',
  routes: [
    GoRoute(
      path: '/setup',
      builder: (context, state) => const SetupScreen(),
    ),
    GoRoute(
      path: '/threads',
      builder: (context, state) => const ThreadListScreen(),
    ),
    GoRoute(
      path: '/chat/:threadId',
      builder: (context, state) => ChatScreen(
        threadId: state.pathParameters['threadId']!,
      ),
    ),
    GoRoute(
      path: '/inspector',
      builder: (context, state) => const FrameInspectorScreen(),
    ),
  ],
);
