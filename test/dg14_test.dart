import 'package:flutter_test/flutter_test.dart';
import 'package:passport_reader/core/asn1/der.dart';
import 'package:passport_reader/core/passport/dg14.dart';
import 'package:passport_reader/core/utils/bytes.dart';

// Real-format DG14 files built with OpenSSL keys (no real passport data).
// A: named brainpoolP256r1 key, AES-128 Chip Authentication, key id 1,
//    plus a Terminal Authentication entry that must be ignored.
final _dg14Named = hexToBytes(
  '6e819231818f306a060904007f000702020102305a301406072a8648ce3d0201'
  '06092b240303020801010703420004692d5788c43c6aaea458afde83d26fdf3c'
  '3bd85639f946e7163836599ca756271e9ab068e61c2a7ce13e5dcbbab4bc7e3f'
  'f80276a964015fd2ac1c2cb5d83b230201013012060a04007f00070202030202'
  '020101020101300d060804007f0007020202020101',
);

// B: brainpoolP256r1 with EXPLICIT parameters and no ChipAuthenticationInfo
//    (older passports): must default to 3DES.
final _dg14Explicit = hexToBytes(
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
);

final _brainpoolA = BigInt.parse(
  '7D5A0975FC2C3057EEF67530417AFFE7FB8055C126DC5C6CE94A4B44F330B5D9',
  radix: 16,
);
final _brainpoolOrder = BigInt.parse(
  'A9FB57DBA1EEA9BC3E660A909D838D718C397AA3B561A6F7901E0E82974856A7',
  radix: 16,
);

void main() {
  test('named curve with AES Chip Authentication', () {
    final setup = parseDg14(_dg14Named);
    expect(setup.cipher, ChipAuthCipher.aes128);
    expect(setup.protocolOid, '0.4.0.127.0.7.2.2.3.2.2');
    expect(setup.protocolOidBytes, hexToBytes('04007f00070202030202'));
    expect(setup.keyId, 1);
    expect(
      setup.curve,
      isA<NamedCurve>().having((c) => c.oid, 'oid', '1.3.36.3.3.2.8.1.1.7'),
    );
    expect(setup.publicPoint, hasLength(65));
    expect(setup.publicPoint.first, 0x04);
  });

  test('explicit curve without ChipAuthenticationInfo defaults to 3DES', () {
    final setup = parseDg14(_dg14Explicit);
    expect(setup.cipher, ChipAuthCipher.tripleDes);
    expect(setup.keyId, isNull);
    final curve = setup.curve as ExplicitCurve;
    expect(curve.a, _brainpoolA);
    expect(curve.order, _brainpoolOrder);
  });

  test('classic Diffie-Hellman is reported as unsupported', () {
    final dhOnly = encodeTlv(
      0x6E,
      encodeTlv(
        0x31,
        encodeTlv(0x30, [
          ...encodeTlv(0x06, [
            0x04,
            0x00,
            0x7F,
            0x00,
            0x07,
            0x02,
            0x02,
            0x03,
            0x01,
            0x01,
          ]),
          ...encodeTlv(0x02, [1]),
        ]),
      ),
    );
    expect(() => parseDg14(dhOnly), throwsA(isA<Dg14Exception>()));
  });

  test('truncated or foreign files are rejected cleanly', () {
    expect(
      () => parseDg14(_dg14Named.sublist(0, 40)),
      throwsA(isA<Dg14Exception>()),
    );
    expect(
      () => parseDg14(encodeTlv(0x61, [0x00])),
      throwsA(isA<Dg14Exception>()),
    );
  });
}
