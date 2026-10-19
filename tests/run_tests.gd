extends SceneTree
## Headless test runner. No dependencies.
##
##   godot --headless --path . -s res://tests/run_tests.gd [-- --filter=<text> --junit=<path>]
##
## Runs every test_* method in every tests/{unit,integration}/test_*.gd. A test fails if it
## records a failed assertion or if the engine reports an error while it runs (unless the test
## sets allow_errors). Exits with the number of failures.

const TEST_DIRS: Array[String] = ["res://tests/unit", "res://tests/integration"]


class ErrorCatcher:
	extends Logger
	var mutex := Mutex.new()
	var errors: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		mutex.lock()
		errors.append("%s (%s:%d in %s) %s" % [code, file, line, function, rationale])
		mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func take() -> PackedStringArray:
		mutex.lock()
		var out := errors
		errors = []
		mutex.unlock()
		return out


var _catcher := ErrorCatcher.new()


func _initialize() -> void:
	OS.add_logger(_catcher)
	_run.call_deferred()


func _run() -> void:
	var filter := ""
	var junit := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.trim_prefix("--filter=")
		elif arg.begins_with("--junit="):
			junit = arg.trim_prefix("--junit=")

	var files: Array[String] = []
	for dir in TEST_DIRS:
		_collect(dir, files)
	files.sort()

	var results: Array[Dictionary] = []
	var started := Time.get_ticks_msec()
	for path in files:
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			results.append({"file": path, "name": "(load)", "ok": false, "ms": 0,
					"messages": PackedStringArray(["script failed to load"]) + _catcher.take()})
			continue
		var names: Array[String] = []
		for m in script.get_script_method_list():
			var n: String = m["name"]
			if n.begins_with("test_") and not names.has(n):
				names.append(n)
		for n in names:
			var id := path.get_file().get_basename() + "::" + n
			if not filter.is_empty() and not id.contains(filter):
				continue
			results.append(await _run_one(script, path, n))

	var failed := 0
	for r in results:
		if not r["ok"]:
			failed += 1
			print("FAIL  %s::%s" % [r["file"].get_file(), r["name"]])
			for msg in r["messages"]:
				print("      " + msg.replace("\n", "\n      "))
	print("\n%d passed, %d failed, %d total in %.1f s" % [results.size() - failed, failed,
			results.size(), (Time.get_ticks_msec() - started) / 1000.0])
	if not junit.is_empty():
		_write_junit(junit, results)
	quit(failed)


func _run_one(script: GDScript, path: String, method: String) -> Dictionary:
	_catcher.take()
	var test: Node = script.new()
	root.add_child(test)
	var t0 := Time.get_ticks_msec()
	if test.has_method("before_each"):
		await test.call("before_each")
	await test.call(method)
	if test.has_method("after_each"):
		await test.call("after_each")
	var messages: PackedStringArray = test.get("_failures")
	var errors := _catcher.take()
	if not test.get("allow_errors"):
		for e in errors:
			messages.append("engine error: " + e)
	test.queue_free()
	await process_frame
	return {"file": path, "name": method, "ok": messages.is_empty(), "messages": messages,
			"ms": Time.get_ticks_msec() - t0}


func _collect(dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		_collect(dir.path_join(sub), out)
	for f in d.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir.path_join(f))


func _write_junit(path: String, results: Array[Dictionary]) -> void:
	var failures := 0
	var body := ""
	for r in results:
		var classname: String = r["file"].get_file().get_basename()
		body += '  <testcase classname="%s" name="%s" time="%.3f">' % [classname, r["name"], r["ms"] / 1000.0]
		if not r["ok"]:
			failures += 1
			body += '<failure message="failed">%s</failure>' % "\n".join(r["messages"]).xml_escape()
		body += "</testcase>\n"
	var xml := '<?xml version="1.0" encoding="UTF-8"?>\n<testsuite name="hexr" tests="%d" failures="%d">\n%s</testsuite>\n' \
			% [results.size(), failures, body]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(xml)
