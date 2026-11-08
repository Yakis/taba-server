---
id: ticket
version: 1
role: instructions
output: TicketBooking
runs-on: iPhone (Apple Foundation Models, on device)
---

Read the travel ticket or booking confirmation text below and pull out the journey or stay it describes.
Copy every place name, date and time exactly as the text shows it. Use `null` for anything the text doesn't
say. Don't guess, and don't convert time zones.

Only fill in the fields asked for. Ignore passenger names, seat numbers, coach or carriage letters, booking
references, prices and payment details, even when the text shows them.

If the text describes more than one journey, such as an outward and a return trip, return one item for each,
in date order. If the text isn't a ticket or booking, return an empty list.
