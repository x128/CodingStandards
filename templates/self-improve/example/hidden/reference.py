from decimal import Decimal, ROUND_HALF_UP
from fractions import Fraction

RATES = {'EUR': Fraction(1), 'USD': Fraction('1.10'), 'GBP': Fraction('0.85'), 'CHF': Fraction('0.95'), 'PLN': Fraction('4.30'), 'CZK': Fraction('25.00'), 'SEK': Fraction('11.20'), 'NOK': Fraction('11.60')}

def cents(text): return int(Decimal(text) * 100)
def money(c): return f"{'-' if c < 0 else ''}{abs(c)//100}.{abs(c)%100:02d}"

def equal(amount, participants):
    base, left = divmod(amount, len(participants))
    return {p: base + (1 if i < left else 0) for i, p in enumerate(participants)}

def weights(amount, weighted):
    total = sum(w for _, w in weighted)
    shares = {p: amount * w // total for p, w in weighted}
    left = amount - sum(shares.values())
    order = sorted(range(len(weighted)), key=lambda i: (-weighted[i][1], i))
    for i in order[:left]: shares[weighted[i][0]] += 1
    return shares

def convert_rounding_half_up_for_a_share_not_below_zero(share, currency, home):
    exact = Fraction(share) * RATES[home] / RATES[currency]
    return int((exact + Fraction(1, 2)).__floor__())

def balances(members, expenses, payments, home):
    b = {m: 0 for m in members}
    for e in expenses:
        conv = {p: convert_rounding_half_up_for_a_share_not_below_zero(s, e['currency'], home) for p, s in e['shares'].items()}
        b[e['payer']] += sum(conv.values())
        for p, c in conv.items(): b[p] -= c
        e['home'] = sum(conv.values()); e['conv'] = conv
    for frm, to, amount in payments:
        b[frm] += amount; b[to] -= amount
    return b

def debts(b):
    b = dict(b); out = []
    while any(v != 0 for v in b.values()):
        debtor = min((m for m in b if b[m] < 0), key=lambda m: (b[m], m.lower()))
        creditor = min((m for m in b if b[m] > 0), key=lambda m: (-b[m], m.lower()))
        amount = min(-b[debtor], b[creditor])
        out.append((debtor, creditor, amount)); b[debtor] += amount; b[creditor] -= amount
    return out

def show(title, members, expenses, payments, home):
    b = balances(members, expenses, payments, home)
    print(f"--- {title}")
    for e in expenses:
        print("  expense", e['title'], "shares", {p: money(s) for p, s in e['shares'].items()}, e['currency'], "| converted", {p: money(c) for p, c in e['conv'].items()}, "| home amount", money(e['home']))
    print("  balances", {m: money(v) for m, v in b.items()})
    print("  debts", [(d, c, money(a)) for d, c, a in debts(b)])
    return b

M = ['Ann', 'Bob', 'Cid']
taxi = {'title': 'Taxi', 'currency': 'EUR', 'payer': 'Ann', 'shares': equal(cents('100.00'), ['Bob', 'Cid', 'Ann'])}
show('A1 equal, leftover cent', M, [dict(taxi)], [], 'EUR')
hut = {'title': 'Hut', 'currency': 'EUR', 'payer': 'Bob', 'shares': weights(cents('100.00'), [('Ann', 3), ('Bob', 3), ('Cid', 1)])}
show('A2 weights', M, [dict(hut)], [], 'EUR')
dinner = {'title': 'Dinner, drinks', 'currency': 'USD', 'payer': 'Ann', 'shares': equal(cents('100.00'), ['Ann', 'Bob', 'Cid'])}
show('A4 conversion USD->EUR', M, [dict(dinner)], [], 'EUR')
show('A12 export trip (Taxi + Dinner)', M, [dict(taxi), dict(dinner)], [], 'EUR')
show('A6 USD expense, home GBP', ['Xena', 'Yuri'], [{'title': 'Tickets', 'currency': 'USD', 'payer': 'Xena', 'shares': equal(cents('50.00'), ['Xena', 'Yuri'])}], [], 'GBP')
M4 = ['Ann', 'bob', 'Cid', 'Dan']
e1 = {'title': 'Museum', 'currency': 'EUR', 'payer': 'Ann', 'shares': {'Cid': 4000}}
e2 = {'title': 'Boat', 'currency': 'EUR', 'payer': 'Dan', 'shares': {'bob': 4000}}
show('A7 ties', M4, [dict(e1), dict(e2)], [], 'EUR')
show('A8 after payment bob->Ann 15.00', M4, [dict(e1), dict(e2)], [('bob', 'Ann', 1500)], 'EUR')
show('A17 weights 7.00 over 1,2,2', ['Ann', 'Bob', 'Cid'], [{'title': 'x', 'currency': 'EUR', 'payer': 'Ann', 'shares': weights(700, [('Ann', 1), ('Bob', 2), ('Cid', 2)])}], [], 'EUR')
r = {'title': 'Fuel', 'currency': 'EUR', 'payer': 'Ann', 'shares': {'bob': 4000, 'Cid': 499, 'Dan': 500}}
show('A11 reminders: bob 40.00, Cid 4.99, Dan 5.00', M4, [dict(r)], [], 'EUR')
