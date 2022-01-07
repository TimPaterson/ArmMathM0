
/*
 * sqrtf.s
 *
 * Created: 6/13/2021 5:40:15 PM
 *  Author: Tim Paterson
 */

.syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"
.include "ieee.inc"
.include "options.inc"


// 32-bit IEEE floating-point square root
//
// Entry:
//	r0 = input
// Exit:
//	r0 = root
//
// The calculation will use Newton-Raphson iteration on inverse square root.
// The initial guess will be calculated by subtracting the upper mantissa bits
// from one of two constants -- one for [1, 2) and the other for [2, 4). The
// values were determined using a spreadsheet.
//
// [1, 2) Mlo = 1.2109375; Y0 = Mlo - X / 4; in hex, 0x9B p7 (0x9B / 0x80)
// [2, 4) Mhi = 0.96875;   Y0 = Mhi - X / 8; in hex, 0x7C p7 (0x7C / 0x80)
//
// The guess will have more than 4 bits of accuracy, allowing 3 iterations to
// get to the required accuracy. The notation p7 means there are 7 bits to the
// right of the binary point, and this notation is used throuout the comments.
//
// Mark Owen demonstrates in Qfplib (http://www.quinapalus.com) some clever
// arrangements that simplify the code for an iteration. First, the common
// representation of an iteration is refactored (x = input, y = guess for
// 1/sqrt(x)):
//
// next = 1.5*y - x*y^3/2  =  y - y*(x*y^2 - 1)/2
//
// Note that since y is a guess for 1/sqrt(x), the inner term x*y^2 will
// be close to 1. By computing this so the binary point is left of the
// 32-bit word, the integer portion just falls off.
//
// Owen's implementation is brilliant and very hard to improve upon. If you
// compare this one with his, you will see a great deal of similarity.
//
// This routine has been tested using every mantissa value in [1, 4).

.set	Mlo,	0x9B	// magic number for lo range, [1, 2)
.set	Mhi,	0x7C	// magic number for hi range, [2, 4)


FUNC_START	__sqrtf, sqrtf
	SAVE_REG r4
	lsls	r1, r0, #1		// clear input sign
	beq	Exit			// input is zero, just return it, sign intact
	bcs	ReturnNan		// must not be negative
	lsrs	r1, #MANT_BITS32 + 1	// input exponent
.ifdef NO_DENORMALS
	beq	Exit			// input is zero, just return it
.else
	beq	Denormal
.endif
	cmp	r1, #EXP_SPECIAL32
	beq	Exit			// return NAN or +Infinity
Normalized:
	// Set implied bit
	movs	r2, #1
	lsls	r2, #MANT_BITS32
	orrs	r2, r0
	lsls	r2, #EXP_BITS32		// normalize, clearing exponent

	// r1 = exponent
	// r2 = input mantissa with implied bit set, p31

	movs	r3, #Mhi	// assume [2, 4)
	lsrs	r0, r2, #26	// save top bits [1, 2) p5

	// Result exponent is current exponent / 2
	// Double the bias before halving. Implied bit position will get
	// added at end, so counteract it as well.
	adds	r1, #EXP_BIAS32 - 2
	// exp >>= 1
	asrs	r1, #1
	bcs	1f		// was it odd?
	lsrs	r2, #1		// if not, add leading zero
	movs	r3, #Mlo	// input interval [1, 2)
1:
	// Compute guess by subtracting upper bits from magic number in r3
	subs	r3, r0

	// First iteration
	// r2 = input p30
	// r3 = guess p7, accurate to 4 bits
	lsrs	r0, r2, #12	// x p18
	muls	r0, r3		// x*y, p25
	muls	r0, r3		// x*y^2 p32
	// As described above, we now view r0 as signed and really have
	// x*y^2 - 1, p32
	asrs	r0, #9		// p23
	muls	r0, r3		// y*(x*y^2 - 1) p30 = y*(x*y^2 - 1)/2 p31
	lsls	r3, #24		// y p31
	subs	r3, r0		// y - y*(x*y^2 - 1)/2 p31
	lsrs	r3, #16		// p15

	// Do it again.
	movs	r0, r3		// y p15
	muls	r0, r0		// y^2 p30
	lsrs	r0, #13		// y^2 p17
	lsrs	r4, r2, #15	// x p15
	muls	r0, r4		// x*y^2 p32
	asrs	r0, #10		// p22
	muls	r0, r3		// y*(x*y^2 - 1) p37 = y*(x*y^2 - 1)/2 p38
	asrs	r0, #23		// p15
	subs	r3, r0		// y - y*(x*y^2 - 1)/2 p15

	// For the third iteration, we refactor again, taking into account
	// we don't want y (the next guess), but x*y (the actual root).
	// So it becomes:
	//
	// result = x*y - x*y*(x*y^2 - 1)/2  =  x*y - y*((x*y)^2 - x)/2
	// = x*y + y*(x - (x*y)^2)/2

	// last iteration left x p15 in r4
	muls	r4, r3		// x*y p30, approximate sqrt(x)
	lsrs	r4, #14		// x*y p16
	movs	r0, r4
	muls	r0, r4		// (x*y)^2 p32
	// With binary point at p32, we've dropped the integer bits.
	lsls	r2, #2		// drop upper bits on x as well, p32
	subs	r0, r2, r0	// x - (x*y)^2 p32 = (x - (x*y)^2)/2 p33
	// The next step is to finish calculating the error term that will
	// be added to the root. Since our guess is pretty close by now,
	// the upper bits of this term are zero and we can use a binary
	// point well past 32 bits.
	asrs	r0, #6		// (x - (x*y)^2)/2 p27
	muls	r0, r3		// y*(x - (x*y)^2)/2 p42
	lsls	r4, #7		// x*y p23
	asrs	r0, #17		// y*(x - (x*y)^2)/2 p25

	// Result will be accurate, but rounding is tricky because
	// the error, no matter how small, can straddle a rounding boundary.
	// First check to see if it does by looking at the rounding bit and
	// the guard bit below it:
	//
	// 00 - never round up
	// 01 - maybe round up
	// 10 - maybe round up
	// 11 - always round up
	//
	// This is tested by adding 1 to the guard bit. This will leave the
	// rounding and guard bits:
	//
	// 01 - never round up
	// 10 - maybe round up
	// 11 - maybe round up
	// 00 - already rounded up
	//
	// So if the round bit ends up 1, we need to calculate the final 
	// remainder for rounding.

	adds	r0, #1		// add to guard bit
	asrs	r0, #2		// p23 - round bit to CY
	add	r0, r4		// x*y + y*(x - (x*y)^2)/2 p23 - final result
	bcc	RootDone	// add did not effect CY, this is round bit from asrs

	// Add 1/2 LSB to result, then see if that's too big or too small by
	// squaring it and comparing with x. Only low bits need comparing, the
	// upper ones must be the same.
	lsls	r3, r0, #1	// result p24
	adds	r3, #1		// bump by half a bit
	muls	r3, r3		// (res + 0.5)^2 p48
	lsls	r2, #16		// x p48 (16 low bits left)
	subs	r3, r2		// (res + 0.5)^2 - x p48
	asrs	r3, #31		// sign((res + 0.5)^2 - x)
	subs	r0, r3		// add 1 if negative
RootDone:
	// r0 = result mantissa, proper position with implied bit set
	// r1 = final exponent, adjusted by -1 for adding implied bit
	// root += exp << MANT_BITS32
	lsls	r1, #MANT_BITS32
	adds	r0, r1
Exit:
	EXIT	r4

.ifndef NO_DENORMALS
Denormal:
	// r0 = input
	// r1 = exponent, currently zero
	push	{r5, r6}
	movs	r4, r0		// pass value
	// __clz_denormal uses tailored calling convention
	// r4 = input to count leading zeros
	// r0 - r3, r7 preserved
	// r5, r6 trashed
	bl	__clz_denormal	// Get leading zeros
	subs	r4, #EXP_BITS32
	lsls	r0, r4
	movs	r1, #1
	subs	r1, r4
	pop	{r5, r6}
	b	Normalized
.endif

ReturnNan:
	ldr	r0, =#NAN32
.ifdef NO_DENORMALS
	b	Exit		// two-instruction return
.else
	pop	{r4, pc}
.endif

	.endfunc
