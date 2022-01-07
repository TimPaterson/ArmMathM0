/*
 * ieee.inc
 *
 * Created: 6/22/2020 5:23:27 PM
 *  Author: Tim
 */ 


// IEEE single
// Bit fields
.set	MANT_BITS32,	23
.set	EXP_BITS32,	8
.set	EXP_BIAS32,	((1 << (EXP_BITS32 - 1)) - 1)
.set	EXP_MIN32,	(-EXP_BIAS32 + 1)
.set	EXP_SPECIAL32,	((1 << EXP_BITS32) - 1)
.set	SIGN_BIT32,	(1LL << 31)

// Special values
.set	INFINITY32,	EXP_SPECIAL32 << MANT_BITS32
// Quiet NAN has MSB of mantissa set
.set	NAN32,		INFINITY32 | (1 << (MANT_BITS32 - 1))

// IEEE double
.set	MANT_BITS64,	52
.set	MANT_BITS_HI64,	(MANT_BITS64 - 32)
.set	EXP_BITS64,	11
.set	EXP_BIAS64,	((1 << (EXP_BITS64 - 1)) - 1)
.set	EXP_MIN64,	(-EXP_BIAS64 + 1)
.set	EXP_SPECIAL64,	((1 << EXP_BITS64) - 1)

// Special values (high word)
.set	INFINITY64,	EXP_SPECIAL64 << MANT_BITS_HI64
// Quiet NAN has MSB of mantissa set
.set	NAN64,		INFINITY64 | (1 << (MANT_BITS_HI64 - 1))
