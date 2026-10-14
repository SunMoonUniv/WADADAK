/// Immutable wire data. Core HTTP clients never depend on a feature's DB model.
class RunUpload {
  RunUpload({
    required this.id,
    required this.owner,
    required this.startedAt,
    required this.inputs,
  }) : finalSeq = inputs.last['seq'] as int;
  final String id, owner;
  final DateTime startedAt;
  final int finalSeq;
  final List<Map<String, dynamic>> inputs;
}
