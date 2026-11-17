enum ChipAuthStatus {
  passed, // the chip proved it holds DG14's private key
  failed, // it could not answer under the new keys: possible clone
  rejected, // it refused the Chip Authentication command (inconclusive)
  notSupported, // no DG14, or an algorithm we don't support
  notCompleted, // connection lost or another non-cryptographic error
}

class ChipAuthResult {
  final ChipAuthStatus status;
  final String? detail; // technical summary only, never personal data

  const ChipAuthResult(this.status, [this.detail]);

  @override
  String toString() => 'ChipAuthResult(${status.name}, $detail)';
}
