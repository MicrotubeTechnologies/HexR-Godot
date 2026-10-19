extends HexRTest
## At most one write per 100 ms, like the Unity package's Quest buffer.


func test_first_write_is_immediate() -> void:
	var c := HexRWriteCoalescer.new()
	c.push(PackedByteArray([1, 2]))
	assert_eq(c.take_due(5000), PackedByteArray([1, 2]), "first write goes at once")


func test_waits_strictly_more_than_interval() -> void:
	var c := HexRWriteCoalescer.new()
	c.push(PackedByteArray([1]))
	c.take_due(1000)
	c.push(PackedByteArray([2]))
	c.push(PackedByteArray([3]))
	assert_true(c.take_due(1050).is_empty(), "too soon")
	assert_true(c.take_due(1100).is_empty(), "exactly 100 ms is still too soon")
	assert_eq(c.take_due(1101), PackedByteArray([2, 3]), "batched after the interval")
	assert_false(c.has_pending(), "drained")


func test_zero_interval_sends_every_time() -> void:
	var c := HexRWriteCoalescer.new()
	c.min_interval_ms = 0
	c.push(PackedByteArray([1]))
	c.take_due(10)
	c.push(PackedByteArray([2]))
	assert_eq(c.take_due(10), PackedByteArray([2]), "no wait")


func test_take_all_and_clear() -> void:
	var c := HexRWriteCoalescer.new()
	c.push(PackedByteArray([7]))
	c.take_due(0)
	c.push(PackedByteArray([8]))
	assert_eq(c.take_all(10), PackedByteArray([8]), "take_all ignores the interval")
	c.push(PackedByteArray([9]))
	c.clear()
	assert_false(c.has_pending(), "cleared")
