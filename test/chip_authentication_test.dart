import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:passport_reader/core/passport/chip_authentication.dart';
import 'package:passport_reader/core/passport/dg14.dart';
import 'package:passport_reader/core/utils/bytes.dart';

ChipAuthSetup _setup(ChipAuthCipher cipher, {int? keyId}) => ChipAuthSetup(
  protocolOid: '0.4.0.127.0.7.2.2.3.2.2',
  protocolOidBytes: hexToBytes('04007f00070202030202'),
  cipher: cipher,
  curve: const NamedCurve('1.3.36.3.3.2.8.1.1.7'),
  publicPoint: Uint8List(65)..[0] = 0x04,
  keyId: keyId,
);

final _ephemeral = Uint8List.fromList([0x04, ...List.filled(64, 0xAB)]);

void main() {
  test('3DES: one MSE:Set KAT command carrying the key in tag 0x91', () {
    final commands = chipAuthCommands(
      _setup(ChipAuthCipher.tripleDes),
      _ephemeral,
    );
    expect(commands, hasLength(1));
    expect(commands.single.toBytes(), [
      0x00,
      0x22,
      0x41,
      0xA6,
      67,
      0x91,
      65,
      ..._ephemeral,
    ]);
  });

  test(
    'AES: MSE:Set AT with protocol and key id, then GENERAL AUTHENTICATE',
    () {
      final commands = chipAuthCommands(
        _setup(ChipAuthCipher.aes128, keyId: 1),
        _ephemeral,
      );
      expect(commands, hasLength(2));
      expect(commands[0].toBytes(), [
        0x00,
        0x22,
        0x41,
        0xA4,
        15,
        0x80,
        10,
        ...hexToBytes('04007f00070202030202'),
        0x84,
        1,
        1,
      ]);
      expect(commands[1].toBytes(), [
        0x00, 0x86, 0x00, 0x00, 69,
        0x7C, 67, 0x80, 65, ..._ephemeral,
        0x00, // Le: "as much as you have"
      ]);
    },
  );

  test('the proof reads EF.COM by short file id', () {
    expect(proofReadCommand().toBytes(), [0x00, 0xB0, 0x9E, 0x00, 0x08]);
  });

  test('ECDH gives both sides the same 32-byte secret', () {
    final domain = curveDomain(const NamedCurve('1.3.36.3.3.2.8.1.1.7'))!;
    final chip = generateEphemeralKeyPair(domain);
    final phone = generateEphemeralKeyPair(domain);

    final phoneSecret = ecdhSharedSecret(phone.privateKey, chip.publicKey.Q!);
    final chipSecret = ecdhSharedSecret(chip.privateKey, phone.publicKey.Q!);

    expect(phoneSecret, chipSecret);
    expect(phoneSecret, hasLength(32));
  });

  test('a real explicit-parameter key resolves to brainpoolP256r1', () {
    final setup = parseDg14(
      hexToBytes(
        '6e82014a3182014630820142060904007f000702020102308201333081ec0607'
        '2a8648ce3d02013081e0020101302c06072a8648ce3d0101022100a9fb57dba1'
        'eea9bc3e660a909d838d726e3bf623d52620282013481d1f6e5377304404207d'
        '5a0975fc2c3057eef67530417affe7fb8055c126dc5c6ce94a4b44f330b5d904'
        '2026dc5c6ce94a4b44f330b5d9bbd77cbf958416295cf7e1ce6bccdc18ff8c07'
        'b60441048bd2aeb9cb7e57cb2c4b482ffc81b7afb9de27e1e3bd23c23a4453bd'
        '9ace3262547ef835c3dac4fd97f8461a14611dc9c27745132ded8e545c1d54c7'
        '2f046997022100a9fb57dba1eea9bc3e660a909d838d718c397aa3b561a6f790'
        '1e0e82974856a70201010342000435753a4dbfd295c41678fdbd945a0a87cbc8'
        '2a8fbd07b7738f06184d018758fe0094b77c316773abdc8f01a17cb45edde1c9'
        '32a00da865abfa7ea4dc3511c915',
      ),
    );
    final domain = curveDomain(setup.curve);
    expect(domain, isNotNull);
    expect(domain!.n, curveDomain(const NamedCurve('1.3.36.3.3.2.8.1.1.7'))!.n);
    // The OpenSSL key must decode as a valid point on that curve.
    expect(
      () => decodeChipPublicKey(domain, setup.publicPoint),
      returnsNormally,
    );
  });

  test('unknown explicit curves are refused, not guessed', () {
    final fake = ExplicitCurve(
      a: BigInt.one,
      b: BigInt.two,
      generatorX: BigInt.one,
      order: BigInt.two,
    );
    expect(curveDomain(fake), isNull);
  });
}
