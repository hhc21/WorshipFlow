import 'package:firebase_auth/firebase_auth.dart';
import 'package:mocktail/mocktail.dart';

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {}

MockFirebaseAuth buildSignedOutAuth() {
  final auth = MockFirebaseAuth();
  when(() => auth.currentUser).thenReturn(null);
  when(() => auth.authStateChanges()).thenAnswer((_) => Stream.value(null));
  return auth;
}

MockFirebaseAuth buildSignedInAuth({
  required String uid,
  required String email,
  String? displayName,
}) {
  final auth = MockFirebaseAuth();
  final user = MockUser();
  when(() => user.uid).thenReturn(uid);
  when(() => user.email).thenReturn(email);
  when(() => user.displayName).thenReturn(displayName);
  when(() => auth.currentUser).thenReturn(user);
  when(() => auth.authStateChanges()).thenAnswer((_) => Stream.value(user));
  return auth;
}
