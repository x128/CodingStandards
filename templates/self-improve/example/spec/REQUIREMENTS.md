# Tripsplit: what the product does

Tripsplit keeps the shared expenses of people who travel together and tells them who owes whom.

This document is everything the product owner said. The owner cannot be asked.

## 1. Words

- **Trip**: a name, a home currency, members, expenses, payments and a status.
- **Member**: a person in one trip, with a display name.
- **Expense**: a title, a date, an amount in some currency, the member who paid (the payer), the members it was for (the participants), and the way it is split between them.
- **Share**: the part of an expense that one participant has to bear.
- **Payment**: money that one member gave to another member to settle up, in the home currency of the trip.
- **Balance** of a member, in the home currency. Above zero: the others owe this member. Below zero: this member owes.
- **Debt**: "A owes B an amount", worked out from the balances.

Amounts have two decimal places. All sums are exact to the cent.
Dates are calendar days written as `YYYY-MM-DD`. "Today" is the current day on the device.
Supported currencies: EUR, USD, GBP, CHF, PLN, CZK, SEK, NOK.

These hold everywhere in this document:

- **A typed amount.** The user types an amount as digits, with or without a dot and one or two more digits: "12", "12.5", "12.50". Spaces at both ends are ignored. Any other text is not an amount: an empty text, a comma, a sign, a third digit after the dot.
- **A written amount** never has a separator between thousands: "1234.50 EUR".
- **Alphabetical order, ignoring letter case**: both texts are turned to lower case and compared character by character.
- **One message.** When an action is refused, exactly one message is shown: the first one that applies, in the order in which the rules and their messages are written in this document. The status of the trip (rules 2.7 and 2.8) is checked before everything else. The rates service is asked only when everything else has passed. A screen shows at most one message, the one of its latest action: every new action of the user on that screen removes the earlier message.
- The name of a trip and the name of a member cannot be changed. A recorded payment cannot be changed or removed.

## 2. Trips

2.1. A trip name is 1 to 40 characters long after the spaces at both ends are removed. Two trips cannot have names that differ only in letter case. Messages: "Enter a name", "The name is too long", "There is already a trip with this name".

2.2. The home currency is one of the supported currencies. It cannot be changed later.

2.3. A trip is open, settling or closed. A new trip is open.

2.4. "Start settling" moves an open trip to settling. It is refused when the trip has no expenses: "There is nothing to settle".

2.5. "Close" moves a settling trip to closed. It is refused while any member's balance is not zero: "Not everyone has settled up".

2.6. "Reopen" moves a settling or closed trip back to open. "Start settling" on a trip that is not open, "Close" on a trip that is not settling and "Reopen" on an open trip change nothing and show no message.

2.7. In a settling trip, expenses cannot be added, changed or removed, and members cannot be added or removed: "The trip is being settled". Payments can be recorded in an open trip and in a settling trip.

2.8. In a closed trip nothing can be added, changed or removed: "The trip is closed".

2.9. A trip can be deleted in any status. Its members, expenses and payments are deleted with it.

## 3. Members

3.1. A member name is 1 to 30 characters long after trimming. Two members of one trip cannot have names that differ only in letter case. Messages: "Enter a name", "The name is too long", "There is already a member with this name".

3.2. A member can be removed only if the member paid no expense, takes part in no expense and is in no payment: "This member has expenses or payments".

## 4. Expenses

4.1. The title is 1 to 60 characters long after trimming: "Enter a title", "The title is too long".

4.2. The amount is a typed amount above zero and not above 1000000.00: "Enter an amount above zero" (also for a text that is not an amount), "The amount is too large".

4.3. The date is not after today: "The date is in the future".

4.4. The payer is a member of the trip; without a payer: "Choose who paid". There is at least one participant: "Choose who the expense is for". Each participant is a member of the trip. Choosing a member who is already a participant changes nothing, so nobody is listed twice. The payer may or may not be a participant.

4.5. There are three ways to split an expense. The shares are in the currency of the expense.

- **Equally.** Each participant gets the amount divided by the number of participants, rounded down to the cent. The cents that are left over are given out one by one, starting with the first participant, in the order in which the participants were chosen.
- **By exact amounts.** The user enters a share for each participant. A share is a typed amount of zero or more; a share left empty counts as 0.00; any other text: "Enter a share of zero or more". The shares must add up to the amount: "The shares add up to 60.00 EUR, but the expense is 70.00 EUR".
- **By weights.** The user enters a whole number from 1 to 100 for each participant; anything else, also an empty weight: "Enter a weight from 1 to 100". Each share is the amount times the weight, divided by the sum of the weights, rounded down to the cent. The cents that are left over are given out one by one, starting with the highest weight. Of two participants with the same weight, the one chosen earlier comes first.

4.6. An expense in a currency other than the home currency of the trip is converted for the balances. Each share is converted on its own: share × home rate ÷ rate of the expense currency, rounded half up to the cent (one rounding, at the end). The rates are those of the date of the expense. A rate says how many units of a currency one EUR buys. The rate of EUR is 1. The **home amount** of an expense is the sum of its converted shares.

4.7. Rates come from the rates service. The rates of a day, once received, are kept in the app's storage, and the service is not asked again for that day. If the service has no rates for that day, the expense is refused: "No exchange rate for USD on 2026-03-07", and the service is asked again next time. The message names the currency of the expense, and its date is always written as `YYYY-MM-DD`. Rates of a day that lack the currency of the expense or the home currency of the trip count as no rates for that day: nothing is kept. No rate is needed when the expense is in the home currency.

4.8. An expense can be changed or deleted. A changed expense must pass rules 4.1 to 4.7 again.

4.9. "Duplicate" makes a new expense with the same title, amount, currency, payer, participants and split, dated today. It must pass rules 2.7, 2.8 and 4.7 as a new expense dated today.

4.10. While the user types, the expense editor shows the share of each participant that would result, in the currency of the expense, or the message that rule 4.5 would give. While the amount is not a typed amount above zero, or no participant is chosen, it shows no shares and no message. The messages of the other rules appear only when the user saves. Nothing is saved until the user saves.

## 5. Balances and debts

5.1. For each expense, the balance of the payer goes up by the home amount of the expense, and the balance of each participant goes down by that participant's converted share. A payer who is also a participant gets both.

5.2. A payment of an amount from A to B raises the balance of A and lowers the balance of B by that amount.

5.3. Debts are worked out from the balances like this. Take the member who owes the most and the member who is owed the most. The first owes the second the smaller of the two amounts. Reduce both by that amount. Repeat until nobody owes anything. When two members owe the same amount, or are owed the same amount, take the one whose name comes first in alphabetical order, ignoring letter case. The debts are listed in the order in which they were worked out.

5.4. A payment has a payer and a receiver, who are two different members: "Choose two different members" (also when one of them is not chosen). Its amount is a typed amount above zero: "Enter an amount above zero". If the payer owes the receiver nothing in the list of debts at that moment: "Bob does not owe Ann anything". The amount is not more than what the payer owes the receiver in that list: "Bob owes Ann only 40.00 EUR".

5.5. The trip screen always shows the current balances and debts. They change at once when an expense is added, changed or removed, or a payment is recorded, wherever that was done.

## 6. Reminders

6.1. Once a day the system runs the app's daily job. It also runs when no screen is open.

6.2. In every trip that has been settling for 3 days or more (the day of the latest "Start settling" is day 0), every member whose balance is -5.00 or lower gets one notification: "You owe 12.50 EUR for Alps. Open the trip to see whom to pay." The amount is what the member owes in total, and "Alps" is the name of the trip. The amount is always written with the currency code after it. The notification is addressed to the member's name. The job goes through the trips in the order of rule 10.5 and through the members of a trip in the order in which they were added.

6.3. A member is not reminded about the same trip twice on the same day, even when the job runs more than once on that day.

6.4. If a notification cannot be delivered, the other notifications are still sent. The member who was not reached does not count as reminded, so the next run tries again. The job posts a notification first and notes the member as reminded only after that.

## 7. Export

7.1. The trip screen can export the trip as text, to share it. The text has two parts with an empty line between them. Every line ends with a line feed.

```
date,title,payer,amount,currency,home amount
2026-03-02,Taxi,Ann,100.00,EUR,100.00
2026-03-06,"Dinner, drinks",Ann,100.00,USD,90.91

debtor,creditor,amount
Bob,Ann,63.64
Cid,Ann,63.63
```

7.2. The first part has one line for each expense: oldest date first; expenses of one day by title, ignoring letter case; expenses with the same date and title in the order in which they were created. The second part has one line for each debt, in the order of rule 5.3. It is there even when there are no debts; then it is only its header line.

7.3. A field that contains a comma or a double quote is put in double quotes, and each double quote inside it is doubled. Amounts are written with a dot and two decimals, without a currency.

## 8. What the app remembers

8.1. The trip that was opened last. When the app starts, it shows that trip. If there is none, or it was deleted, it shows the list of trips.

8.2. How amounts are shown on screens. "Code": the currency code after the amount, "12.50 EUR". "Symbol": the symbol before the amount, "€12.50" for EUR, "$12.50" for USD, "£12.50" for GBP; the other currencies are shown with the code. The user chooses in the settings. At first it is "Code".

## 9. Screens

The app has no drawing code in this version. A screen is given by what it shows and what the user can do on it.

9.1. **Start.** Decides which screen is shown first (rule 8.1).

9.2. **Trips.** Shows the trips (rule 10.5). The user can create a trip (name, home currency), delete a trip and open a trip.

9.3. **Trip.** Shows the name and the status of the trip, its members in the order in which they were added, each with a balance line (rule 10.2), and the debts (rule 10.3). The user can add a member, remove a member, start settling, close the trip, reopen it, record a payment (payer, receiver, amount) and export the trip. The screen knows which of these the status of the trip allows right now, so that it can switch the other buttons off. It shows the message when something is refused.

9.4. **Expenses** of a trip. Shows the expenses (rule 10.6). The user can type a filter text, delete an expense, duplicate an expense, and open the editor for a new expense or for an existing one. The screen knows whether expenses can be added and changed right now.

9.5. **Expense editor**, for a new expense or an existing one. The user enters the title, the amount, the currency, the date, the payer, the participants (in the order in which they are chosen), the way to split and, for each participant, the exact amount or the weight. The screen shows the shares as the user types (rule 4.10). The editor for a new expense starts with an empty title and amount, the home currency of the trip, today's date, no payer, no participants and the split "Equally". The editor for an existing expense starts with the values of that expense. After a successful save the editor closes.

9.6. **Settings.** The user chooses how amounts are shown (rule 8.2).

## 10. How things are shown

10.1. Amounts on screens follow rule 8.2, in messages too. Export (section 7) and notifications (section 6) do not follow it.

10.2. The balance line of a member: "gets back 12.50 EUR", "owes 12.50 EUR" or "settled up".

10.3. A debt line: "Bob owes Ann 30.30 EUR".

10.4. A date in a list or in the editor: "7 Mar 2026". The day has no leading zero. The month is its first three letters in English. A date inside a message stays as the rule of that message writes it.

10.5. The list of trips: open trips first, then settling ones, then closed ones; trips with the same status by name, ignoring letter case. A row shows the name, the status ("open", "settling", "closed"), the number of members and the total spent: the sum of the home amounts of all expenses of the trip.

10.6. The list of expenses: newest date first; expenses of one day by title, ignoring letter case; expenses with the same date and title in the order in which they were created. A row shows the date, the title and who paid how much: "Ann paid 100.00 USD". With a filter text, only the expenses whose title contains the text, ignoring letter case, are shown.

## 11. Failures

If the app cannot read or write its storage, cannot reach the rates service, or anything else fails that this document does not describe, the screen shows "Something went wrong. Try again." and stays usable.
