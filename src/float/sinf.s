
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

.set	COS_X_EQUALS_1_EXP,	-12
.set	ONE,			EXP_BIAS32 << MANT_BITS32
.set	PI_MANTISSA,		0XC90FDAA2	// p30 for pi, p32 for pi/4
.set	ONE_OVER_PI_MANTISSA,	0xA2F9836E	// p33 for 1/pi, p31 for 4/pi
.set	ATAN_OF_HALF,		0x76B19C16	// p32
.set	ATAN_OF_2_TO_MINUS_8,	0x3FFFEAAB	// p38

.set	SMALL_ANGLE_SHIFT,	7


	.func	__sinf

SpecialExp:
	// If argument is NAN, return it for both sin() and cos().
	// If it's infinity, make a new NAN and return it for both.
	lsls	r2, r0, #(EXP_BITS32 + 1)	// mantissa == 0?
	bne	ReturnOp	// input is NAN, return it
ReturnNan:
	ldr	r0, =#NAN32
ReturnOp:
	movs	r1, r0
	pop	{r4-r7, pc}


ENTRY_POINT	__sinf, sinf
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
	subs	r1, EXP_BIAS32 - 1
	blt	FullyReduced

	// r1 = unbiased exponent + 1, >= 0
	// r2 = input mantissa, MSB set
	// r7 = input sign
	//
	// Calculate the number of multiples of pi/4
	ldr	r3, =#ONE_OVER_PI_MANTISSA >> 16	// p15
	lsrs	r4, r2, #16	// input p16 for exponent + 1 == 0
	muls	r3, r4		// p31 for exponent + 1 == 0
	movs	r4, #31
	subs	r4, r1		// no. of bits < 1
	blt	ReturnNan	// if immense, return NAN to say we can't do it
	lsrs	r3, r4		// floor(input/(pi/4)) p0
	beq	VerifyOctant	// speed up angles <= pi/4
	ldr	r0, =#PI_MANTISSA	// MSB set, p32 for pi/4
	mov	r12, r7
	mul32x32	r3, r0, r4, r0, r5, r6, r7
	mov	r7, r12
	// r0:r4 = multiple of pi/4, p31
	// r1 = unbiased exponent + 1, >= 0
	// r2 = input mantissa, MSB set
	// r3 = quotient
	// r7 = input sign
	movs	r5, #32
	subs	r5, r1		// no. of leading zeros
	// 64-bit left shift to normalize
	lsls	r0, r5
	movs	r6, r4
	lsls	r4, r5
	lsrs	r6, r1
	orrs	r0, r6
	// remove pi/4 multiples, exactly
	negs	r4, r4
	sbcs	r2, r0		
	lsl64short	r4, r2, r1, r6
VerifyOctant:
	// Our calculation of the number of pi/4 mulitples could be short.
	ldr	r0, =#PI_MANTISSA	// MSB set, p32 for pi/4
	cmp	r2, r0
	blo	CheckOctant
	adds	r3, #1
	subs	r2, r0
CheckOctant:
	// if odd-numbered octant, subtract from pi/4
	lsrs	r5, r3, #1
	bcc	SaveOctant
	subs	r2, r0, r2
SaveOctant:
	eors	r7, r3		// invert octant if negative
	movs	r1, #0		// exponent + 1 for reduced angle
FullyReduced:
	// Range reduction could have introduced any number of leading
	// zeros. See if there are enough to divert to the small angle
	// loop.
	mov	r12, r7		// save octant info
	lsrs	r3, r2, #32 - SMALL_ANGLE_SHIFT
	beq	SmallAngleUnnormal
	// input domain [0, pi/4]
	// r1 = unbiased exponent + 1
	// r2 = mantissa 
	// r12 = octant info
	adds	r3, r1, #SMALL_ANGLE_SHIFT - 1
	blt	SmallAngle
	negs	r1, r1
	lsrs	r2, r1		// mantissa p32

	// The first CORDIC rotation is based on whether the input angle
	// is positive or negative. Since our range reduction ensures
	// it's positive, we can hard-code the first rotation. Also,
	// since input <= pi/4, we can skip over the tan() == 1 rotation.
	// So the first rotation from the table is tan() == 0.25, a
	// shift of 2 bits.

.set	SHIFT_START,	2

	ldr	r1, =#SCALE
	lsrs	r0, r1, #1
	adr	r3, AtanTable
	movs	r4, #SHIFT_START - 1	// we increment first thing
	ldr	r5, =#ATAN_OF_HALF	// Simulate tan() = 0.5 rotation
	subs	r2, r5
	movs	r5, #0
	// r0 = y p32 (becomes sin)
	// r1 = x p32 (becomes cos)
	// r2 = z p32 (current error in angle)
	// r3 = ptr to table of angles [atan(2^-i)]
	// r4 = iteration i (and shift count)
	// r5 = extended y p64
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
LoopTail:
	cmp	r4, #SHIFT_END
	bne	RotLoop
LoopDone:
	// r0 = y p32 (becomes sin)
	// r1 = x p32 (becomes cos)
	// r2 = z p32 (current error in angle)
	// r5 = extended y p64
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
	// Normalize the y signed result. Minimum value 2^-6.
Normalize:
	// r0 = y
	// r1 = x p32 uncorrected
	// r2 = exponent of y
	// r5 = extended y p63
	// r7 = correction for x p42
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
	movs	r4, #0
	lsrs	r0, #EXP_BITS32 + 1	// position mantissa
	adcs	r0, r4		// add rounding bit
	adds	r0, r2		// combine exponent

	// Correct the result for original octant
	// Octant info in r12:
	// bit 0: original argument sign
	// bits 1-3: octant number
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
	movs	r2, r0
	movs	r0, r1
	movs	r1, r2
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
	// r2 = mantissa, at least -COS_X_EQUALS_1_EXP leading zeros
	// r12 = octant info
	subs	r1, #-COS_X_EQUALS_1_EXP
	lsls	r2, #-COS_X_EQUALS_1_EXP	// get rid of some leading zeros
	beq	ZeroSine
	bmi	QuickExit
SmallNormLoop:
	subs	r1, #1
	lsls	r2, #1
	bpl	SmallNormLoop
QuickExit:
	// r1 = unbiased exponent + 1
	// r2 = normalized mantissa (MSB set)
	// r12 = octant info
	lsls	r0, r2, #1	// clear off implied bit
	adds	r1, #EXP_BIAS32 - 1
	movs	r2, r1
	ldr	r1, =#ONE
	// r0 = y, fully left justified w/o implied bit
	// r1 = fully completed cosine
	// r2 = exponent of y
	// r12 = octant info
	b	CombineSine

SmallAngleUnnormal:
	// We can 
	// r1 = unbiased exponent + 1
	// r2 = mantissa, at least SMALL_ANGLE_SHIFT leading zeros
	// r12 = octant info
	// 
	// Check for more leading zeros for quick exit
	lsrs	r4, r2, #32 + COS_X_EQUALS_1_EXP
	beq	QuickExitUnnormal
	lsls	r2, #SMALL_ANGLE_SHIFT - 1

SmallAngle:
	// r1 = unbiased exponent + 1
	// r2 = normalized mantissa (MSB set)
	// r3 = unbiased exponent + SMALL_ANGLE_SHIFT, < 0
	negs	r3, r3
	cmp	r3, -COS_X_EQUALS_1_EXP - SMALL_ANGLE_SHIFT
	bgt	QuickExit
	lsrs	r2, r3		// mantissa p38

	// Like the main CORDIC loop, we can hard code the first rotation
	// since the angle is always positive.

.set	SMALL_SHIFT_START,	2

	ldr	r1, =#SMALL_SCALE
	lsrs	r0, r1, #1
	adr	r3, SmallAtanTable
	movs	r4, #SMALL_SHIFT_START - 1	// we increment first thing
	ldr	r5, =#ATAN_OF_2_TO_MINUS_8	// Simulate tan() = 2^-8 rotation
	subs	r2, r5
	// r0 = y p39 (becomes sin)
	// r1 = x p32 (becomes cos)
	// r2 = current error in angle p38
	// r3 = ptr to table of angles [atan(2^-i)]
	// r4 = iteration i (and shift count)
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
	b	Normalize

	.ltorg
AtanTable:
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
.set	SHIFT_END, (. - AtanTable) / 4 + SHIFT_START - 1

// The scale factor is the product of the cosines of all the angles in
// the table, so it depends on table length.
// Scale for p32
.if	SHIFT_END <= 10
.error	"No scale factor for selected atan table size."
.elseif	SHIFT_END == 11
.set	SCALE, 0xDBD95BA9
.elseif	SHIFT_END == 12
.set	SCALE, 0xDBD95B3B
.elseif	SHIFT_END == 13
.set	SCALE, 0xDBD95B20
.else
.set	SCALE, 0xDBD95B19
.endif
/*
// Scale for p31
.if	SHIFT_END <= 10
.error	"No scale factor for selected atan table size."
.elseif	SHIFT_END == 11
.set	SCALE, 0x6DECADD5
.elseif	SHIFT_END == 12
.set	SCALE, 0x6DECAD9E
.elseif	SHIFT_END == 13
.set	SCALE, 0x6DECAD90
.else
.set	SCALE, 0x6DECAD8C
.endif
*/

SmallAtanTable:
	.word	0x1FFFFD55
	.word	0xFFFFFAB
	.word	0x7FFFFF5
	.word	0x3FFFFFF
	.word	0x2000000
	//.word	0x1000000
.set	SMALL_SHIFT_END, (. - SmallAtanTable) / 4 + SMALL_SHIFT_START - 1

// Scale for p32
.if	SMALL_SHIFT_END < 4 || SMALL_SHIFT_END > 7
.error	"No scale factor for small angle atan table size."
.elseif	SMALL_SHIFT_END == 4
.set	SMALL_SCALE, 0xFFFF5600
.elseif	SMALL_SHIFT_END == 5
.set	SMALL_SCALE, 0xFFFF5580
.elseif	SMALL_SHIFT_END == 6
.set	SMALL_SCALE, 0xFFFF5560
.elseif	SMALL_SHIFT_END == 7
.set	SMALL_SCALE, 0xFFFF5558
.endif
/*
// Scale for p31
.if	SMALL_SHIFT_END < 4 || SMALL_SHIFT_END > 6
.error	"No scale factor for small angle atan table size."
.elseif	SMALL_SHIFT_END == 4
.set	SMALL_SCALE, 0x7FFFAB00
.elseif	SMALL_SHIFT_END == 5
.set	SMALL_SCALE, 0x7FFFAAC0
.elseif	SMALL_SHIFT_END == 6
.set	SMALL_SCALE, 0x7FFFAAB0
.endif
*/

	.endfunc
