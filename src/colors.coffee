# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Standardized color hex definitions
# TODO: Generate these colors programatically

Imm = require 'immutable'

# Darker color spectrum for programs
ProgramColors = Imm.List [
	"#cf1d1d"
	"#cf1d5c"
	"#cf1da7"
	"#c51dcf"
	"#7d1dcf"
	"#3f1dcf"
	"#1d4bcf"
	"#1d92cf"
	"#1dc0cf"
	"#1dcfa3"
	"#1dcf36"
	"#86cf1d"
	"#a3cf1d"
	"#cfb41d"
	"#e35c27"
	"#cf691d"
]

# Brighter color spectrum for event types
EventTypeColors = Imm.List [
	"#f06767"
	"#f067a4"
	"#f067db"
	"#c467f0"
	"#9167f0"
	"#6777f0"
	"#6794f0"
	"#67b4f0"
	"#67ebf0"
	"#67f0cb"
	"#67f06d"
	"#97b45f"
	"#d6d13f"
	"#f0c867"
	"#f0a167"
	"#f08467"
]

# TODO: Metrics colors (#975)

module.exports = {
	ProgramColors
	EventTypeColors
}