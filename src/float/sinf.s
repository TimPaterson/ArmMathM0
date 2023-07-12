
/*
 * sinf.s
 *
 * Created: 6/6/2023 5:46:38 PM
 *  Author: Tim
 */

.syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"
.include "ieee.inc"
.include "options.inc"
.include "trigf.inc"


// 32-bit floating-point sine
//
// Entry:
//	r0 = input angle in radians
// Exit:
//	r0 = sine
//	r1 = cosine
//
// The calculation will use CORDIC rotation on an input range reduced to
// [0, pi/4], which produces both the sine and cosine. Fixed-point math
// is used, which loses relative accuracy for small input. To counter
// this, there is a separate calculation for small angles.
//
// If the angle is very small, we can just return sin(x) = x and cos(x) = 1.
// The series for cos(x) starts with
//	cos(x) = 1 - x^2/2 + ...
// So we return cos(x) = 1 (and sin(x) = x) if x^2/2 < 2^-25, or x < 2^-12.
//
// The "p" notation used throughout is the position of the binary point
// (p16 means there are 16 bits to the right).


.set	FINE_REDUCTION_MAX_BITS, 8
.set	FINE_REDUCTION_MAX,	(1 << FINE_REDUCTION_MAX_BITS) - 1	// max multiples of pi/4 for lossless reduction
.set	PI_HI,			PI_MANTISSA >> FINE_REDUCTION_MAX_BITS
LSR	PI_MID32,		PI_MANTISSA_LO, PI_MANTISSA, 2 * FINE_REDUCTION_MAX_BITS// shift into position
.set	PI_MID,			PI_MID32 & ((1 << (32 - FINE_REDUCTION_MAX_BITS)) - 1)
.set	PI_LO,			(PI_MANTISSA_LO >> FINE_REDUCTION_MAX_BITS) & ((1 << FINE_REDUCTION_MAX_BITS) - 1)
.set	SMALL_ANGLE_SHIFT,	7	// shift in y for small angles
.set	SHIFT_START,		2	// first rotation is atan(2^-2)
.set	SHIFT_END,		SINE_ATAN_TABLE_ENTRIES - 1 + SHIFT_START - 1
.set	SMALL_SHIFT_START,	2
.set	SMALL_SHIFT_END,	SMALL_SINE_ATAN_TABLE_ENTRIES - 1 + SMALL_SHIFT_START - 1
.set	SCALE,			0xDBD95B20	// product of cosines, p32
.set	SMALL_SCALE,		0xFFFF5560	// product of cosines in small table, p38
.ifdef WIDE_TRIG_RANGE
.set	MAX_VALID_EXP,		14	// less than 2^15 radians allowed
.else
.set	MAX_VALID_EXP,		7	// less than 2^8 radians allowed
.endif


	.func	__sinfM0

SpecialExp:
	// If argument is NAN, return it for both sin() and cos().
	// If it's infinity, make a new NAN and return it for both.
	lsls	r2, r0, #(EXP_BITS32 + 1)	// mantissa == 0?
	bne	ReturnOp	// input is NAN, return it
.ifndef WIDE_TRIG_RANGE
BigReduction:
.endif
ReturnNan:
	ldr	r0, =#NAN32
ReturnOp:
	movs	r1, r0
	pop	{r4-r7, pc}


.ifdef WIDE_TRIG_RANGE

BigReduction:
	// r1 = unbiased exponent + 1, >= 0, <= 15
	// r2 = input mantissa, MSB set
	// r3 = floor(input/(pi/4)) p0
	// r4 = input >> 16
	// r5 = 31 - r1
	// r6 = 4/pi * input p31
	// r7 = input sign
	//
	// Reduction is > FINE_REDUCTION_MAX * pi/4. Calculate it
	// more exactly with 32x24 multiply of input*(4/pi).
	ldr	r3, =#ONE_OVER_PI_MANTISSA
	uxth	r0, r3
	muls	r0, r4		// 4/pi lo16 * input hi16
	lsrs	r4, r2, #8
	uxtb	r4, r4
	lsrs	r3, #8
	muls	r3, r4		// 4/pi hi24 * input lo8
	// sum partial products
	adds	r3, r0
	bcc	SumIt
	MOV_IMM	r4, 0x10000
	adds	r6, r4
SumIt:
	lsrs	r3, #16
	adds	r3, r6		// complete input * 4/pi = input/(pi/4)
	lsrs	r3, r5		// floor(input/(pi/4)) p0

	// now create that exact multiple of pi/4
	// use a 16x64 multiply to get exact result
	mov	r12, r7
	ldr	r0, =#PI_MANTISSA_LO
	uxth	r4, r0			// low half pi lo
	muls	r4, r3
	lsls	r6, r4, #16		// extended result
	lsrs	r4, #16			// in position
	lsrs	r0, #16			// high half pi lo
	muls	r0, r3
	adds	r4, r0			// sum bottom two partial products
	ldr	r0, =#PI_MANTISSA
	uxth	r7, r0			// low half pi hi
	muls	r7, r3
	lsrs	r0, #16			// high half of pi hi
	muls	r0, r3
	lsrs	r5, r7, #16		// align for sum
	lsls	r7, #16
	adds	r4, r7
	adcs	r0, r5
	// r0:r4:r6 = multiple of pi/4
	// set up normalization shift count
	movs	r5, #16
	subs	r5, r1
	lsl96short	r6, r4, r0, r5, r7	// 64-bit left shift to normalize
	mov	r7, r12
	// r0:r4 = multiple of pi/4, p32
	// r1 = unbiased exponent + 1, >= 0
	// r2 = input mantissa, MSB set
	// r3 = quotient
	// r7 = input sign, 0 or -1
	b	HaveReductionProduct

.endif	// WIDE_TRIG_RANGE


ENTRY_POINT	__sinfM0, sinf
	push	{r4-r7, lr}
	lsls	r1, r0, #1		// clear input sign
	lsrs	r1, #MANT_BITS32 + 1	// isolate exponent
	cmp	r1, #EXP_SPECIAL32
	beq	SpecialExp
	asrs	r7, r0, #31		// save input sign
	movs	r2, #1
	lsls	r2, #MANT_BITS32	// implied bit position
	orrs	r2, r0
	lsls	r2, #EXP_BITS32		// isolate mantissa
	movs	r4, #0			// extend mantissa
	subs	r1, EXP_BIAS32 - 1	// r1 = unbiased exp. + 1
	blt	FullyReduced		// already < 0.5 radians?
	cmp	r1, #MAX_VALID_EXP + 1
	bgt	ReturnNan		// if immense, return NAN to say we can't do it

	// r1 = unbiased exponent + 1, >= 0, <= 15
	// r2 = input mantissa, MSB set
	// r7 = input sign
	//
	// Calculate the number of multiples of pi/4
	ldr	r3, =#ONE_OVER_PI_MANTISSA >> 16	// 4/pi p15
	lsrs	r4, r2, #16	// input p16
	muls	r3, r4		// p31
	movs	r5, #31
	subs	r5, r1
.ifdef WIDE_TRIG_RANGE
	movs	r6, r3
.endif
	lsrs	r3, r5		// floor(input/(pi/4)) p0
	cmp	r3, #FINE_REDUCTION_MAX
	bhi	BigReduction
	ldr	r0, =#PI_HI
	muls	r0, r3
	ldr	r4, =#PI_MID
	muls	r4, r3		// partial products overlap by FINE_REDUCTION_MAX_BITS
	lsrs	r6, r4, #32 - FINE_REDUCTION_MAX_BITS
	adds	r0, r6
	lsls	r4, #FINE_REDUCTION_MAX_BITS
	ldr	r6, =#PI_LO
	muls	r6, r3
	adds	r4, r6		// r0:r4 = pi/4 reduction
	bcc	1f
	adds	r0, #1		// propagate carry
1:
	// r0:r4 = multiple of pi/4
	// r1 = unbiased exponent + 1, >= 0
	// r2 = input mantissa, MSB set
	// r3 = quotient
	// r5 = 31 - r1
	// r7 = input sign, 0 or -1
	subs	r5, #31 - FINE_REDUCTION_MAX_BITS	// = FINE_REDUCTION_MAX_BITS - r1
	lsl64short	r4, r0, r5, r6		// 64-bit left shift to normalize
HaveReductionProduct:
	// remove pi/4 multiples, exactly
	negs	r4, r4
	sbcs	r2, r0
	// r1 = unbiased exponent + 1, >= 0
	// r2:r4 = input mod pi/4
	// r3 = quotient (octant)
	// r7 = input sign, 0 or -1
	lsl64short	r4, r2, r1, r6
	ldr	r0, =#PI_MANTISSA	// MSB set, p32 for pi/4
	ldr	r5, =#PI_MANTISSA_LO
	// Our calculation of the number of pi/4 mulitples could be short 1.
	//
	// r0 - pi/4 mantissa p32
	// r2:r4 = reduced input p32
	// r3 = tentative octant (zero-based)
	// r7 = input sign,  0 or -1
	cmp	r2, r0
	blo	CheckOctant
	adds	r3, #1
	subs	r4, r5
	sbcs	r2, r0
CheckOctant:
	// if odd-numbered octant, subtract from pi/4
	lsrs	r6, r3, #1
	bcc	SaveOctant
	subs	r4, r5, r4
	sbcs	r0, r2
	movs	r2, r0
SaveOctant:
	eors	r7, r3		// invert octant if negative
	movs	r1, #0		// exponent + 1 for reduced angle
FullyReduced:
	// Range reduction could have introduced any number of leading
	// zeros. See if there are enough to divert to the small angle
	// loop.
	//
	// r1 = unbiased exponent + 1, <= 0
	// r2:r4 = input mantissa
	// r7 = octant info
	mov	r12, r7		// save octant info
	ldr	r3, =#__sineAtanTable
	lsrs	r5, r2, #32 - SMALL_ANGLE_SHIFT
	beq	SmallAngleUnnormal
	// input domain [0, pi/4]
	// r1 = unbiased exponent + 1
	// r2 = mantissa
	// r12 = octant info
	//
	// round the reduced angle in r2:r4
	lsls	r4, #1
	bcc	1f
	adds	r2, #1
1:
	adds	r4, r1, #SMALL_ANGLE_SHIFT - 1
	blt	SmallAngle
	negs	r1, r1
	lsrs	r2, r1		// mantissa p32

	// The first CORDIC rotation is based on whether the input angle
	// is positive or negative. Since our range reduction ensures
	// it's positive, we can hard-code the first rotation. Also,
	// since input <= pi/4, we can skip over the tan() == 1 rotation.
	// So the first rotation from the table is tan() == 0.25, a
	// shift of 2 bits.

	ldr	r1, =#SCALE
	lsrs	r0, r1, #1
	movs	r4, #SHIFT_START - 1	// we increment first thing
	ldmia	r3!, {r5}		// tan() = 0.5 rotation
	subs	r2, r5
	movs	r5, #0
	// r0 = y p32 (becomes sin)
	// r1 = x p32 (becomes cos)
	// r2 = z p32 (current error in angle)
	// r3 = ptr to table of angles [atan(2^-i)]
	// r4 = iteration i (and shift count)
	// r5 = extended y p64
	// r12 = octant info
RotLoop:
	adds	r4, #1
	movs	r6, #32
	subs	r6, r4
	movs	r7, r1
	lsls	r7, r6
	movs	r6, r1
	lsrs	r6, r4		// r6:r7 = r1 >> r4 = x * 2^-i
	cmp	r2, #0
	blt	TooSmall
	adds	r5, r7
	mov	r7, r0
	adcs	r0, r6		// y += x * 2^-i
	lsrs	r7, r4		// y * 2^-i
	subs	r1, r7		// x -= y * 2^-i
	ldmia	r3!, {r6}	// next atan()
	subs	r2, r6		// new angle
	cmp	r4, #SHIFT_END
	bne	RotLoop
	b	LoopDone

TooSmall:
	subs	r5, r7
	mov	r7, r0
	sbcs	r0, r6		// y -= x * 2^-i
	lsrs	r7, r4		// y * 2^-i
	adds	r1, r7		// x += y * 2^-i
	ldmia	r3!, {r6}	// next atan()
	adds	r2, r6		// new angle
	cmp	r4, #SHIFT_END
	bne	RotLoop
LoopDone:
	// r0 = y p32 (becomes sin)
	// r1 = x p32 (becomes cos)
	// r2 = z p32 (current error in angle)
	// r5 = extended y p64
	// r12 = octant info
	//
	// We have used CORDIC to get us x (cos) and y (sin) of an angle
	// very close to our target. The remaining error angle z is so
	// small that (in 24-bit precision) cos(z) = 1 and sin(z) = z.
	// This allows us to simplify the rotation formula:
	// x' = x*cos(z) - y*sin(z) => x' = x - y*z
	// y' = x*sin(z) + y*cos(z) => y' = x*z + y
	// So we can compute that last rotation in one shot.
	// |z| <= last table entry, 2^-13 (20 bits incl. sign, p32)
	// 0 < y <= sqrt(2), sqrt(2) <= x < 1

	// Final computation of y for sine
	lsrs	r4, r1, #20	// keep 12 of 32 bits, p12
	muls	r4, r2		// high product, p44
	lsls	r6, r1, #12	// trim off the bits we just used
	lsrs	r6, #20		// next 12 bits, p24
	muls	r6, r2		// low product, p56
	lsls	r7, r6, #8	// low p64
	asrs	r6, #24		// low p32
	lsls	r3, r4, #20	// hi p64
	asrs	r4, #12		// hi p32
	adds	r3, r7
	adcs	r4, r6		// r4:r3 = adjustment p64
	lsrs	r7, r0, #16	// Keep 16 bits of y before we hammer it, p16
	adds	r5, r3
	adcs	r0, r4

	// Final computation of x for cosine
	asrs	r6, r2, #6	// Keep 14 bits of z, p26
	muls	r7, r6		// p42

	movs	r2, #EXP_BIAS32	// exponent
	// Normalize the y result. Minimum value 2^-6.
Normalize:
	// r0 = y
	// r1 = x p32 uncorrected
	// r2 = exponent of y
	// r5 = extended y p63
	// r7 = correction for x p42
	// r12 = octant info
	asrs	r7, #10		// p32
	subs	r1, r7
NormLoop:
	subs	r2, #1
	adds	r5, r5
	adcs	r0, r0
	bcc	NormLoop	// until we shift off MSB

	// r0 = y
	// r1 = x, sqrt(2) <= x < 1, p32
	// r2 = exponent of y
	// r12 = octant info
	movs	r4, #0
	lsrs	r1, #EXP_BITS32	// position mantissa
	adcs	r1, r4		// add rounding bit
	movs	r4, #EXP_BIAS32 - 2	// implied bit will add 1
	lsls	r4, #MANT_BITS32	// position exponent
	adds	r1, r4		// combine exponent
CombineSine:
	// r0 = y, fully left justified w/o implied bit
	// r1 = fully completed cosine
	// r2 = exponent of y
	// r12 = octant info
	lsls	r2, #MANT_BITS32	// position exponent
	lsrs	r0, #EXP_BITS32 + 1	// position mantissa
	adcs	r0, r2		// combine exponent and rounding bit

	// Correct the result for original octant
	// Bits 0-2: octant number
	//  octant  |  swap | sin | cos
	//     0    |    no |  +  |  +
	//     1    |   yes |  +  |  +
	//     2    |   yes |  +  |  -
	//     3    |    no |  +  |  -
	//     4    |    no |  -  |  -
	//     5    |   yes |  -  |  -
	//     6    |   yes |  -  |  +
	//     7    |    no |  -  |  +
	//		  ^    ^     ^
	// (octant+1) & 2 |    |     |
	//	    octant & 4 |     |
	//	      (octant+2) & 4 |
	//
	// r0 = sine
	// r1 = cosine
	// r12 = octant info

	mov	r3, r12
	adds	r4, r3, 1	// add to octant bit 0
	lsrs	r4, #2		// octant bit 1 to CY
	bcc	SetSigns
	// swap sin and cos
	SWAP	r0, r1
SetSigns:
	adds	r4, r3, 2	// add to octant bit 1
	lsrs	r4, #2		// isolate octant bit 2
	lsls	r4, #31
	orrs	r1, r4		// set sign of cosine
	lsrs	r4, r3, #2	// isolate octant bit 2
	lsls	r4, #31
	orrs	r0, r4		// set sign of sine
	pop	{r4-r7, pc}

ZeroSine:
	movs	r1, #0		// set exponent to zero too
	b	QuickExit

QuickExitUnnormal:
	// r1 = unbiased exponent + 1
	// r2:r4 = mantissa, at least -COS_X_EQUALS_1_EXP leading zeros
	// r12 = octant info
	subs	r1, #-COS_X_EQUALS_1_EXP
	lsl64const	r4, r2, -COS_X_EQUALS_1_EXP, r6	// get rid of some leading zeros
	beq	ZeroSine
	bmi	QuickExit
SmallNormLoop:
	subs	r1, #1
	adds	r4, r4
	adcs	r2, r2
	bpl	SmallNormLoop
QuickExit:
	// r1 = unbiased exponent + 1
	// r2 = normalized mantissa (MSB set)
	// r12 = octant info
	lsls	r0, r2, #1	// clear off implied bit
	adds	r1, #EXP_BIAS32 - 1
	movs	r2, r1
	MOV_IMM	r1, ONE32
	// r0 = y, fully left justified w/o implied bit
	// r1 = fully completed cosine
	// r2 = exponent of y
	// r12 = octant info
	b	CombineSine

SmallAngleUnnormal:
	// r2:r4 = mantissa, at least SMALL_ANGLE_SHIFT leading zeros
	// r3 = __sineAtanTable pointer
	// r12 = octant info
	//
	// Check for more leading zeros for quick exit
	lsrs	r5, r2, #32 + COS_X_EQUALS_1_EXP
	beq	QuickExitUnnormal
	lsl64const	r4, r2, SMALL_ANGLE_SHIFT - 1, r6
	// round the reduced angle in r2:r4
	lsls	r4, #1
	bcc	SmallStartCordic
	adds	r2, #1
	b	SmallStartCordic

SmallAngle:
	// r2 = normalized mantissa (MSB set)
	// r3 = __sineAtanTable pointer
	// r4 = unbiased exponent + SMALL_ANGLE_SHIFT, < 0
	// r12 = octant info
	negs	r4, r4
	cmp	r4, #-COS_X_EQUALS_1_EXP - SMALL_ANGLE_SHIFT
	bgt	QuickExit
	lsrs	r2, r4		// mantissa p38

SmallStartCordic:
	// r2 = normalized mantissa (MSB set)
	// r3 = __sineAtanTable pointer
	// r12 = octant info
	//
	// Like the main CORDIC loop, we can hard code the first rotation
	// since the angle is always positive.
	ldr	r1, =#SMALL_SCALE
	lsrs	r0, r1, #1
	adds	r3, #SMALL_SINE_ATAN_TABLE_OFFSET
	movs	r4, #SMALL_SHIFT_START - 1	// we increment first thing
	ldmia	r3!, {r5}	// tan() = 2^-8 rotation
	subs	r2, r5
	// r0 = y p39 (becomes sin)
	// r1 = x p32 (becomes cos)
	// r2 = current error in angle p38
	// r3 = ptr to table of angles [atan(2^-i)]
	// r4 = iteration i (and shift count)
	// r12 = octant info
SmallRotLoop:
	adds	r4, #1
	ldmia	r3!, {r5}	// next atan()
	lsrs	r7, r0, #2*SMALL_ANGLE_SHIFT
	lsrs	r7, r4		// y * 2^-i
	movs	r6, r1
	lsrs	r6, r4		// x * 2^-i
	cmp	r2, #0
	blt	SmallTooSmall
	subs	r1, r7		// x -= y * 2^-i
	adds	r0, r6		// y += x * 2^-i
	subs	r2, r5		// new angle
	cmp	r4, #SMALL_SHIFT_END
	bne	SmallRotLoop
	b	SmallLoopDone

SmallTooSmall:
	adds	r1, r7		// x += y * 2^-i
	subs	r0, r6		// y -= x * 2^-i
	adds	r2, r5		// new angle
	cmp	r4, #SMALL_SHIFT_END
	bne	SmallRotLoop
SmallLoopDone:
	// r0 = y p39 (becomes sin)
	// r1 = x p32 (becomes cos)
	// r2 = z p38 (current error in angle)
	// r12 = octant info
	// |z| <= last table entry, 26 bits incl. sign
	// 0 < y < 1
	// 0 < x < 1

	lsls	r3, r2, #1	// z, p39
	mul32sx32hi	r3, r1, r4, r5, r6, r7	// upper product, p(39+32-32) = p39
	lsrs	r7, r0, #20	// Keep 12 bits of y before we hammer it, p19
	adds	r0, r4		// y p39

	// Now finish x
	asrs	r6, r2, #15	// Keep 12 bits of z, p23
	muls	r7, r6		// p42

	// Prepare to normalize
	movs	r2, #EXP_BIAS32 - SMALL_ANGLE_SHIFT	// exponent
	movs	r5, #0
	// r0 = y
	// r1 = x p32 uncorrected
	// r2 = exponent of y
	// r5 = extended y p63
	// r7 = correction for x p42
	// r12 = octant info
	b	Normalize

	.endfunc
