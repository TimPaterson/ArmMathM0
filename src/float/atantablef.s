
/*
 * atantablef.s
 *
 * Created: 7/28/2023 12:40:29 PM
 *  Author: Tim
 */ 

.syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"
.include "ieee.inc"
.include "options.inc"
.include "trigf.inc"


// Tables of arc tangents for sinf() and atan2f() functions. Both 
// functions switch to a table with higher precision when the
// argument is small.
//
// The "p" notation used throughout is the position of the binary point 
// (p16 means there are 16 bits to the right).

	.global	__fullAtanTable
	.global	__sineAtanTable

	.align	2

__fullAtanTable:
	.word	0
__sineAtanTable:
	// tan(2^-i), i = 1 .. 13, p32
	.word	0x76B19C16
	.word	0x3EB6EBF2
	.word	0x1FD5BA9B
	.word	0xFFAADDC
	.word	0x7FF556F
	.word	0x3FFEAAB
	.word	0x1FFFD55
	.word	0xFFFFAB
	.word	0x7FFFF5
	.word	0x3FFFFF
	.word	0x200000
	.word	0x100000
	.word	0x80000
AtanTableEnd:

SmallAtanTable:
	// tan(2^-i), i = 7 .. 13, p38
	.word	0x7FFF5557
SineSmallAtanTable:
	.word	0x3FFFEAAB
	.word	0x1FFFFD55
	.word	0xFFFFFAB
	.word	0x7FFFFF5
	.word	0x3FFFFFF
	.word	0x2000000
SmallAtanTableEnd:

// Verify constants in trigf.inc

.if	ATAN_TABLE_END_OFFSET != AtanTableEnd - __fullAtanTable
.error	"Error: ATAN_TABLE_END_OFFSET constant in trigf.inc does not match actual offset."
.endif

.if	SMALL_ATAN_TABLE_OFFSET != SmallAtanTable - __fullAtanTable
.error	"Error: SMALL_ATAN_TABLE_OFFSET constant in trigf.inc does not match actual offset."
.endif

.if	SMALL_ATAN_TABLE_END_OFFSET != SmallAtanTableEnd - AtanTableEnd
.error	"Error: SMALL_ATAN_TABLE_END_OFFSET constant in trigf.inc does not match actual offset."
.endif

.if	SMALL_SINE_ATAN_TABLE_OFFSET != SineSmallAtanTable - __sineAtanTable
.error	"Error: SMALL_SINE_ATAN_TABLE_OFFSET constant in trigf.inc does not match actual offset."
.endif

.if	SINE_ATAN_TABLE_ENTRIES != (AtanTableEnd - __sineAtanTable) / 4
.error	"Error: SINE_ATAN_TABLE_ENTRIES constant in trigf.inc does not match actual count."
.endif

.if	SMALL_SINE_ATAN_TABLE_ENTRIES != (SmallAtanTableEnd - SineSmallAtanTable) / 4
.error	"Error: SMALL_SINE_ATAN_TABLE_ENTRIES constant in trigf.inc does not match actual count."
.endif
