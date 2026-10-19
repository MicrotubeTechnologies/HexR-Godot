// Cuts a batch of glove frames into writes that fit one packet (MTU - 3), on frame boundaries.
// The glove ignores longer writes. Same rules as HexRFrames.chunk_for_mtu (GDScript) and
// FrameChunker.java; all three are checked against tests/fixtures/frames_split.json.
#pragma once

#include <cstdint>
#include <vector>

namespace hexr {

inline std::vector<std::vector<uint8_t>> split_frames(const std::vector<uint8_t> &data) {
	std::vector<std::vector<uint8_t>> out;
	size_t i = 0;
	while (i < data.size()) {
		size_t length = data[i];
		if (length == 0 || length > data.size() - i) {
			break; // the firmware stops walking here too
		}
		out.emplace_back(data.begin() + i, data.begin() + i + length);
		i += length;
	}
	return out;
}

inline std::vector<std::vector<uint8_t>> chunk_for_mtu(const std::vector<uint8_t> &data, int max_payload) {
	std::vector<std::vector<uint8_t>> out;
	if (data.empty()) {
		return out;
	}
	if (max_payload <= 0 || data.size() <= static_cast<size_t>(max_payload)) {
		out.push_back(data);
		return out;
	}
	std::vector<uint8_t> current;
	for (const auto &frame : split_frames(data)) {
		if (!current.empty() && current.size() + frame.size() > static_cast<size_t>(max_payload)) {
			out.push_back(current);
			current.clear();
		}
		current.insert(current.end(), frame.begin(), frame.end());
	}
	if (!current.empty()) {
		out.push_back(current);
	}
	return out;
}

} // namespace hexr
