// Display only. Window matching belongs to the database, using the factory timezone.
export function shiftWindow(shift) {
  if (!shift?.start_time || !shift?.end_time) return null;
  const a=String(shift.start_time),b=String(shift.end_time);
  const display=value=>value.length>5 && value.slice(6)!=='00'?value:value.slice(0,5);
  return {start:display(a),end:display(b),overnight:a>b};
}
