import 'package:file_chat/core/auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? ok(String e) => Auth.canonicalEmail(e).email;
  String? err(String e) => Auth.canonicalEmail(e).error;

  test('one Gmail inbox is one account', () {
    expect(ok('5azuy2@gmail.com'), '5azuy2@gmail.com');
    expect(ok(' 5.Azuy.2@GMAIL.com '), '5azuy2@gmail.com');
    expect(ok('5azuy2@googlemail.com'), '5azuy2@gmail.com');
  });

  test('aliases and unknown mail services are refused', () {
    expect(err('5azuy2+b78@gmail.com'), 'email-alias');
    expect(err('me+x@outlook.com'), 'email-alias');
    expect(err('someone@mailinator.com'), 'email-domain');
    expect(err('someone@10minutemail.com'), 'email-domain');
    expect(err('not-an-email'), 'invalid-email');
  });

  test('dots stay where they matter', () {
    expect(ok('john.smith@hotmail.com'), 'john.smith@hotmail.com');
    expect(ok('John.Smith@Outlook.com'), 'john.smith@outlook.com');
  });
}
