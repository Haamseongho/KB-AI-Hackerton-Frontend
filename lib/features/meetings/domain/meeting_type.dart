enum MeetingType {
  general('unknown', 'General'),
  oneOnOne('one_on_one', '1:1'),
  small('small', 'Small'),
  medium('medium', 'Medium'),
  unknown('unknown', 'Unknown');

  const MeetingType(this.value, this.label);

  final String value;
  final String label;
}
