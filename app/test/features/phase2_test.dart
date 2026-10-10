import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:app/core/auth/auth_service.dart';
import 'package:app/features/friends/data/friends_repository.dart';
import 'package:app/features/auth/presentation/merge_explainer_screen.dart';
import 'package:app/core/theme/app_theme.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Phase 2 Flutter Unit & Feature Tests', () {
    test('StubAuthService supports OTP flow, Google sign-in, and session restore', () async {
      final authService = StubAuthService();

      // Test OTP
      await authService.sendOtp('9876543210');
      final result = await authService.verifyOtp('9876543210', '123456');

      expect(result.user.phoneE164, '+919876543210');
      expect(result.token, contains('Bearer user:'));

      // Test Google sign-in
      final googleResult = await authService.signInWithGoogle();
      expect(googleResult.user.id, 'usr_arhaam');
      expect(googleResult.user.email, 'arhaam@splitup.app');

      // Test session restore
      final restored = await authService.restoreSession();
      expect(restored, isNotNull);
      expect(restored!.id, 'usr_arhaam');

      // Test sign out
      await authService.signOut();
    });

    test('FriendsRepository handles adding friends and private nickname editing', () async {
      final repo = FriendsRepository();
      final initialFriends = await repo.fetchFriends();
      expect(initialFriends.isNotEmpty, true);

      // Add a registered app user contact
      final addedAppUser = await repo.addFriend(phone: '9876543211', name: 'Rahul Test');
      expect(addedAppUser.isAppUser, true);
      expect(addedAppUser.name, 'Rahul Test');

      // Add a placeholder non-app contact
      final addedPlaceholder = await repo.addFriend(phone: '9988776655', name: 'Zack Offline');
      expect(addedPlaceholder.isAppUser, false);

      // Update private nickname
      await repo.updateNickname(addedAppUser.id, 'My Best Friend');
      final friendsAfterUpdate = await repo.fetchFriends();
      final updatedFriend = friendsAfterUpdate.firstWhere((f) => f.id == addedAppUser.id);
      expect(updatedFriend.nickname, 'My Best Friend');
      expect(updatedFriend.resolvedName, 'My Best Friend');

      // Unsettled balance guard test: cannot remove if netPaise != 0
      final friendWithDebt = initialFriends.firstWhere((f) => f.netPaise != 0);
      expect(
        () async => await repo.removeFriend(friendWithDebt.id),
        throwsA(isA<Exception>()),
      );
    });

    testWidgets('MergeExplainerScreen renders first launch summary properly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const MergeExplainerScreen(
            expenseCount: 5,
            totalPaise: 250000,
            inviterName: 'Priya',
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Welcome to SplitUp!'), findsOneWidget);
      expect(find.textContaining('Priya already added you to expenses'), findsOneWidget);
      expect(find.text('5 expenses'), findsOneWidget);
      expect(find.text('₹2,500'), findsOneWidget);
      expect(find.text('Continue to SplitUp'), findsOneWidget);
    });
  });
}
