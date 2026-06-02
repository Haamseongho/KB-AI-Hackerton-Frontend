enum MeetingType {
  general('unknown', '일반'),
  oneOnOne('one_on_one', '1:1'),
  small('small', '소규모'),
  medium('medium', '중규모'),
  unknown('unknown', '알 수 없음');

  const MeetingType(this.value, this.label);

  final String value;
  final String label;
}
