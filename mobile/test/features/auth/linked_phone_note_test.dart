import 'package:axon_pos/features/auth/data/linked_phone_note.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('remembers which phone signed this computer in', () async {
    expect(await LinkedPhoneNote.read(), isNull);

    await LinkedPhoneNote.save(device: "John's phone", person: 'John');
    final note = await LinkedPhoneNote.read();

    expect(note?.label, "John's phone");
    expect(note?.person, 'John');
  });

  test('falls back to the approver name when the phone sent no name', () async {
    await LinkedPhoneNote.save(person: 'Ada');
    expect((await LinkedPhoneNote.read())?.label, "Ada's phone");
  });

  test('nothing is saved when the service sent no phone details', () async {
    await LinkedPhoneNote.save();
    expect(await LinkedPhoneNote.read(), isNull);

    await LinkedPhoneNote.save(device: "John's phone");
    await LinkedPhoneNote.clear();
    expect(await LinkedPhoneNote.read(), isNull);
  });
}
