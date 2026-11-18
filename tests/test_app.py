from tests.common import check_common, cleanup, client, query

check_common()

# Normal path.
client.post("/wishes", data={"item": "Example headphones", "price": "199.99", "wait_days": "7"})
client.post("/wishes", data={"item": "Example gadget", "price": "50", "wait_days": "0"})
assert query("SELECT item, price, wait_days, status FROM wishes ORDER BY id") == [
    ("Example headphones", 199.99, 7, "waiting"), ("Example gadget", 50.0, 0, "waiting")]

# Invalid input and boundaries.
for bad in ({"item": "", "price": "10"}, {"item": "X", "price": "-1"}, {"item": "X", "price": "abc"},
            {"item": "X", "price": "nan"}, {"item": "X", "price": "10", "wait_days": "366"},
            {"item": "X", "price": "10", "wait_days": "-1"}, {"item": "x" * 121, "price": "10"}):
    client.post("/wishes", data=bad)
assert len(query("SELECT id FROM wishes")) == 2, "invalid wish was stored"

headphones = query("SELECT id FROM wishes WHERE item = 'Example headphones'")[0][0]
gadget = query("SELECT id FROM wishes WHERE item = 'Example gadget'")[0][0]

# Buying is blocked during the cooling-off period.
client.post(f"/wishes/{headphones}/decide", data={"status": "bought"})
assert query("SELECT status FROM wishes WHERE id = ?", (headphones,)) == [("waiting",)]

# Skipping is always allowed and counts as money not spent.
client.post(f"/wishes/{gadget}/decide", data={"status": "skipped"})
assert query("SELECT status FROM wishes WHERE id = ?", (gadget,)) == [("skipped",)]
assert b"$50.00" in client.get("/").data

# A decision cannot be changed afterwards.
client.post(f"/wishes/{gadget}/decide", data={"status": "bought"})
assert query("SELECT status FROM wishes WHERE id = ?", (gadget,)) == [("skipped",)]

# Invalid status and unknown items.
assert client.post(f"/wishes/{headphones}/decide", data={"status": "maybe"}).status_code == 400
assert client.post("/wishes/999999/decide", data={"status": "skipped"}).status_code == 404

cleanup()
print("Should I Buy It tests passed.")
