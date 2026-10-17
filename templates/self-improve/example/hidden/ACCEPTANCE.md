# Acceptance scenarios

Unless a scenario says otherwise: today is 2026-03-10; rates are those of the demo rates service
(USD 1.10, GBP 0.85 per EUR on working days; no rates on 2026-03-07 and 2026-03-08, which are a Saturday and a Sunday);
amounts are shown as "Code". Members are added in the order in which they are named.
"Screen shows" means: the state of that screen's ViewModel holds this text.

S01 Trip names (2.1). Creating a trip named "   " is refused: "Enter a name". A name of 41 letters: "The name is too long". A name of 40 letters is accepted. With a trip "Alps", creating "alps" or " ALPS " is refused: "There is already a trip with this name".

S02 Equal split (4.5, 5.1, 5.3, 10.2, 10.3). Trip "Alps", EUR, members Ann, Bob, Cid. Expense "Taxi", 100.00 EUR, 2026-03-02, paid by Ann, for Bob, Cid, Ann (chosen in this order), split equally. Trip screen shows: Ann "gets back 66.67 EUR", Bob "owes 33.34 EUR", Cid "owes 33.33 EUR"; debts, in this order: "Bob owes Ann 33.34 EUR", "Cid owes Ann 33.33 EUR".

S03 Weights (4.5, 4.10). Same trip without the taxi. Editor: "Hut", 100.00 EUR, 2026-03-02, paid by Bob, for Ann (weight 3), Bob (weight 3), Cid (weight 1). The editor shows the shares 42.86, 42.86 and 14.28 EUR before saving. After saving: Ann "owes 42.86 EUR", Bob "gets back 57.14 EUR", Cid "owes 14.28 EUR". A second check of the rule alone: 7.00 over weights 1, 2, 2 gives 1.40, 2.80, 2.80.

S04 Exact amounts that do not add up (4.5, 4.10). Editor: 70.00 EUR for Bob 30.00 and Cid 30.00. The editor shows "The shares add up to 60.00 EUR, but the expense is 70.00 EUR" while typing and again on save. Nothing is saved.

S05 Conversion (4.6, 10.5). Trip "Alps", EUR, members Ann, Bob, Cid. Expense "Dinner, drinks", 100.00 USD, 2026-03-06, paid by Ann, for Ann, Bob, Cid, equally. Shares 33.34, 33.33, 33.33 USD become 30.31, 30.30, 30.30 EUR. Trip screen: Ann "gets back 60.60 EUR", Bob "owes 30.30 EUR", Cid "owes 30.30 EUR". The list of trips shows the total spent 90.91 EUR.

S06 No rate (4.7). The same expense dated 2026-03-07 is refused: "No exchange rate for USD on 2026-03-07". Nothing is saved. An expense of 10.00 EUR dated 2026-03-07 in the same trip is accepted.

S07 Home currency other than EUR (4.6). Trip "London", GBP, members Xena, Yuri. Expense "Tickets", 50.00 USD, 2026-03-06, paid by Xena, for Xena and Yuri equally. Xena "gets back 19.32 GBP", Yuri "owes 19.32 GBP".

S08 Debts with equal amounts (5.3). Trip, EUR, members Ann, bob (lower case), Cid, Dan. "Museum", 40.00 EUR, paid by Ann, for Cid only. "Boat", 40.00 EUR, paid by Dan, for bob only. Debts, in this order: "bob owes Ann 40.00 EUR", "Cid owes Dan 40.00 EUR".

S09 Payments (5.4). In the trip of S08, which is open: a payment from bob to Dan of 10.00 is refused: "bob does not owe Dan anything". From bob to Ann 50.00: "bob owes Ann only 40.00 EUR". From bob to Ann "0.00", "" or "12,50": "Enter an amount above zero". From bob to bob 10.00: "Choose two different members". From bob to Ann 15.00 is accepted; the debts are then, in this order: "Cid owes Dan 40.00 EUR", "bob owes Ann 25.00 EUR".

S10 Status (2.3 to 2.8, 9.3). A new trip with a member but no expenses: start settling is refused: "There is nothing to settle". After an expense: start settling works, the status is "settling". Then adding an expense, changing or deleting one, adding or removing a member are refused: "The trip is being settled", and the trip screen says these actions are not possible now. Close is refused: "Not everyone has settled up". After payments that bring every balance to zero, close works. Then a payment is refused: "The trip is closed". Reopen works from closed and from settling; after it an expense can be added. "Close" on an open trip and "Start settling" on a closed trip change nothing and show no message.

S11 Members (3.1, 3.2). With a member "Ann", adding "ann" is refused: "There is already a member with this name"; "" gives "Enter a name"; 31 letters give "The name is too long". Removing a member who paid or takes part in an expense, or is in a payment, is refused: "This member has expenses or payments". A member with none of these is removed.

S12 Reminders (section 6). Trip "Alps", EUR, members Ann, bob, Cid, Dan. "Fuel", 49.99 EUR, paid by Ann, exact amounts: bob 40.00, Cid 4.99, Dan 5.00. Settling started on 2026-03-07. The daily job on 2026-03-10 delivers exactly two notifications: to "bob": "You owe 40.00 EUR for Alps. Open the trip to see whom to pay."; to "Dan": "You owe 5.00 EUR for Alps. Open the trip to see whom to pay.". A second run on the same day delivers nothing more. If Dan cannot be reached on the first run, bob still gets his; a later run on the same day with Dan reachable delivers Dan's and not bob's again. With settling started on 2026-03-08, a run on 2026-03-10 delivers nothing, and a run on 2026-03-11 delivers both. The text does not change when amounts are shown as "Symbol". An open or closed trip gets no reminders.

S13 Export (section 7). Trip "Alps", EUR, members Ann, Bob, Cid, with the taxi of S02 and the dinner of S05. The exported text is exactly:

date,title,payer,amount,currency,home amount
2026-03-02,Taxi,Ann,100.00,EUR,100.00
2026-03-06,"Dinner, drinks",Ann,100.00,USD,90.91

debtor,creditor,amount
Bob,Ann,63.64
Cid,Ann,63.63

with a line feed at the end of every line. A title `Say "hi"` is written as `"Say ""hi"""`. A trip with no debts ends with the header line `debtor,creditor,amount`.

S14 Duplicate (4.9). Duplicating the taxi makes a second expense with the same title, amount, currency, payer, participants and split, dated 2026-03-10. With today 2026-03-08, duplicating the dinner is refused: "No exchange rate for USD on 2026-03-08"; duplicating the taxi works. In a settling trip duplicating is refused: "The trip is being settled".

S15 Live update (5.5). A trip screen is open. An expense is saved through the expense editor of the same trip. The balances and debts of the open trip screen change without anything being asked of the trip screen.

S16 Failures (section 11). Storage that cannot be read (`Store(directory, broken = true)`): the trips screen shows "Something went wrong. Try again.". A rates service that cannot be reached (a RatesClient with any URL other than the demo one): saving a USD expense shows "Something went wrong. Try again.", nothing is saved, and an EUR expense can be saved right after it on the same screen.

S17 Amount display (8.2, 10.1). After the user chooses "Symbol": the trip of S02 shows "gets back €66.67"; the trip of S07 shows "gets back £19.32"; a trip with home currency PLN still shows amounts as "12.50 PLN". Messages follow it too: the message of S09 reads "bob owes Ann only €40.00". The choice survives a restart.

S18 Last opened trip (8.1). After a trip was opened and the app is started again on the same storage, the start shows that trip. After that trip is deleted and the app is started again, the start shows the list of trips. With fresh storage the start shows the list of trips.

S19 Lists (9.3, 10.4 to 10.6). Members added as Cid, Ann, Bob are shown on the trip screen in that order. Trips "beta" (open), "Alpha" (open), "Gamma" (settling), "Delta" (closed) are listed as Alpha, beta, Gamma, Delta, each with its status word and the number of members. Expenses dated 2026-03-02 "b", 2026-03-06 "a", 2026-03-06 "B" are listed as "a", "B" (both 6 Mar 2026), then "b" (2 Mar 2026). A row reads like "Ann paid 100.00 USD". The filter "DIN" keeps only expenses whose title contains "din" in any letter case.

S20 Rates are kept (4.7). After a USD expense dated 2026-03-06 was saved, a second USD expense with the same date does not ask the rates service again, also after a restart on the same storage. After a refusal for 2026-03-07 the next attempt for that date asks the service again.

S21 Delete a trip (2.9). After a trip with members, expenses and payments is deleted, it is not in the list, and nothing of it is left in storage. If it was the trip opened last, the next start shows the list.

S22 Change an expense (4.8). Changing the taxi of S02 to 90.00 EUR changes the balances to Ann "gets back 60.00 EUR", Bob "owes 30.00 EUR", Cid "owes 30.00 EUR". Changing its date to 2026-03-11 is refused: "The date is in the future". Changing its currency to USD with the date 2026-03-07 is refused: "No exchange rate for USD on 2026-03-07".

S23 Expense fields (4.1 to 4.5). Title "" gives "Enter a title"; 61 letters give "The title is too long". Amount "0.00", "", "abc", "12,50" or "10.005" gives "Enter an amount above zero"; "1000000.01" gives "The amount is too large"; "1000000.00" is accepted; " 12.5 " is 12.50. No payer: "Choose who paid". No participants: "Choose who the expense is for". A payer who is not a participant is accepted. A weight of 0, 101, "1.5" or "" gives "Enter a weight from 1 to 100". An exact share "-5" gives "Enter a share of zero or more"; an exact share left empty counts as 0.00.

S24 One message, in order (section 1). In a settling trip, saving an expense with an empty title shows "The trip is being settled". In an open trip, saving an expense with an empty title, the amount "0" and no payer shows only "Enter a title". After a refused action, the next action of the user on that screen removes the message. While the amount field of the editor is empty, the editor shows no shares and no message.

S25 Same date and title (7.2, 10.6). Two expenses "Taxi" dated 2026-03-02, of 10.00 and then of 20.00, are listed and exported with the 10.00 one first.
