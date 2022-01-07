
/*
 * faddsub.s
 *
 * Created: 8/6/2021 12:33:35 PM
 *  Author: Tim
 */

.syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"
.include "ieee.inc"
.include "options.inc"


// 32-bit IEEE floating-point add & subtract
//
// Entry:
//	r0 = op1
//	r1 = op2
// Exit:
//	r0 = op1 + op2
//	   or
//	r0 = op1 - op2

FUNC_START	__fsub, __aeabi_fsub
	movs	r2, #1
	lsls	r2, #31
	eors	r1, r2		// flip sign for subtract
	//
	// fall into fadd
	//
ENTRY_POINT	__fadd, __aeabi_fadd

.ifdef	NO_DENORMALS

	// Handle easy cases before saving registers
	//
	// If one of the operands is zero, just return the
	// other -- including if it's NAN or infinity.
	lsls	r3, r1, #1	// clear op2 sign
	lsrs	r3, #MANT_BITS32 + 1	// op2 exponent
	beq	ReturnOp1
	lsls	r2, r0, #1	// clear op1 sign
	lsrs	r2, #MANT_BITS32 + 1	// op1 exponent
	beq	ReturnOp2

	cmp	r3, #EXP_SPECIAL32
	beq	Op2SpclExp
	// If op1 is special (and op2 not), just return op1
	cmp	r2, #EXP_SPECIAL32
	beq	ReturnOp1

	push	{r4, r5, r7}

	movs	r5, #1
	lsls	r5, #31		// sign position
	lsrs	r7, r0, #31	// grab sign of op1
	movs	r4, r0
	eors	r4, r1		// see if signs the same
	ands	r4, r5		// isolate sign bit
	orrs	r7, r4		// combine sign info

.else

	push	{r4, r5, r7, lr}

	movs	r5, #1
	lsls	r5, #31		// sign position
	lsrs	r7, r0, #31	// grab sign of op1
	movs	r4, r0
	eors	r4, r1		// see if signs the same
	ands	r4, r5		// isolate sign bit
	orrs	r7, r4		// combine sign info

	lsls	r2, r0, #1	// clear op1 sign
	lsls	r3, r1, #1	// clear op2 sign
	lsrs	r2, #MANT_BITS32 + 1	// op1 exponent
	beq	Op1ZeroExp
Op1Normalized:
	lsrs	r3, #MANT_BITS32 + 1	// op2 exponent
	beq	Op2ZeroExp
Op2Normalized:

	cmp	r3, #EXP_SPECIAL32
	beq	Op2SpclExp
	// If op1 is special (and op2 not), just return op1
	cmp	r2, #EXP_SPECIAL32
	beq	ReturnOp1

.endif

	// r0 = op1
	// r1 = op2
	// r2 = op1 exponent
	// r3 = op2 exponent
	// r5 = 0x80000000 (sign bit position)
	// r7 = bit 0 = sign of op1, bit 31 = sign xor

	// Clear exponent, set implied bit
	lsls	r0, #EXP_BITS32
	lsls	r1, #EXP_BITS32
	orrs	r0, r5
	orrs	r1, r5
	// align so bit 30 is MSB
	lsrs	r0, #1
	lsrs	r1, #1

	subs	r5, r2, r3	// op1 exp - op2 exp
	negs	r4, r5		// op2 exp - op1 exp
	bmi	Op1Larger
	// op2 is larger
	movs	r2, r3		// save exponent
	cmp	r4, #MANT_BITS32 + 3	// include implied, round & sticky bits
	bhi	UseOp2
	adds	r5, #32		// no. of bits to shift off for sticky bits
	movs	r3, r0
	lsls	r3, r5		// sticky bits
	lsrs	r0, r4		// align op1
CheckSign:
	orrs	r7, r7		// check sign flags
	bmi	SubOp1		// signs were different, subtract
AddOps:
	// signs are the same, add operands
	// r0 = op1 mantissa, MSB at bit 30
	// r1 = op2 mantissa, aligned to match r0 exponent
	// r2 = result exponent
	// r3 = sticky bits
	// r7 = bit 0 is sign of result
	adds	r0, r1		// sum it
	// Operand MSB was at bit 30, leaving room for it to carry into
	// bit 31. A one-bit normalization will be needed if it didn't.
	bmi	Round
Norm1bit:
	subs	r2, #1		// adjust exponent
	lsls	r0, #1		// normalize
Round:
	// r0 = result, left justified
	// r2 = result exponent - 1
	// r3 = sticky bits
	// r7 = bit 0 is sign of result
	cmp	r2, #EXP_SPECIAL32 - 1
	bhs	BigExp
	lsls	r4, r0, #25	// look at everything below rounding bit
Align:
	lsrs	r0, #8		// normal alignment, rounding bit to CY
	bcc	Aligned		// if CY not set, no rounding needed
	orrs	r3, r4		// any sticky bits?
	bne	RoundUp
	lsls	r3, r0, #31	// check LSB for even
	bpl	Aligned		// if even, leave it
RoundUp:
	adds	r0, #1		// add to rounding bit
Aligned:
	lsls	r2, #MANT_BITS32
	adds	r0, r2
SetSign:
	lsls	r7, #31
	adds	r0, r7
Exit:
.ifdef	NO_DENORMALS
	pop	{r4, r5, r7}
ReturnOp1:
	bx	lr

ReturnOp2:
	movs	r0, r1
	bx	lr
.else
	pop	{r4, r5, r7, pc}

ReturnOp2:
	movs	r0, r1
ReturnOp1:
	pop	{r4, r5, r7, pc}

.endif

Op1Larger:
	// op1 has a larger exponent, so it's bigger for sure
	cmp	r5, #MANT_BITS32 + 3	// implied, round & sticky bits
	bhi	Norm1bit	// op1 is result
	adds	r4, #32		// no. of bits to be shifted off
	movs	r3, r1
	lsls	r3, r4		// sticky bits
	lsrs	r1, r5		// align op2
	orrs	r7, r7		// check sign flags
	bpl	AddOps
	// op1 - op2
	negs	r3, r3		// 0 - sticky bits
	sbcs	r0, r1
	b	Normalize

UseOp2:
	movs	r0, #0
	b	CheckSign

SubOp1:
	// op2 - op1
	// However, it could be op2 <= op1 with same exponent
	adds	r7, #1		// flip sign bit in LSB
	negs	r3, r3		// 0 - sticky bits
	sbcs	r1, r0
	movs	r0, r1
	beq	Exit		// Return zero result
	bpl	Normalize
	// Subtracted wrong way. Can't be any sticky bits
	adds	r7, #1		// flip sign bit in LSB
	negs	r0, r0
Normalize:
	// Check for big chunks of leading zeros
.set	NORM1,	12
	lsrs	r1, r0, #31 - NORM1
	bne	1f
	subs	r2, #NORM1	// adjust exponent
	lsls	r0, #NORM1	// normalize a bunch
1:
.set	NORM2,	6
	lsrs	r1, r0, #31 - NORM2
	bne	2f
	subs	r2, #NORM2	// adjust exponent
	lsls	r0, #NORM2	// normalize a bunch
2:
	// Finish off bit-by-bit
NormLoop:
	subs	r2, #1		// adjust exponent
	lsls	r0, #1		// normalize one bit
	bpl	NormLoop
	b	Round

Op2SpclExp:
	// r0 = op1
	// r1 = op2
	// r2 = op1 exponent
	// r3 = op2 exponent
	//
	// op2 mantissa == 0?
	lsls	r3, r1, #(EXP_BITS32 + 1)
	bne	ReturnOp2	// op2 is NAN, return it
	// op2 is Infinity
	// if (expOp1 == EXP_SPECIAL)
	cmp	r2, #EXP_SPECIAL32
	bne	ReturnOp2	// op1 not special, return op2
	// op1 mantissa == 0?
	lsls	r3, r0, #(EXP_BITS32 + 1)
	bne	ReturnOp1	// op1 is NAN, return it
	// Both op1 & op2 are infinity. If signs differ, return NAN
	eors	r1, r0
	bpl	ReturnOp1	// signs the same, return infinity
	// return NAN
	ldr	r0, =#NAN32
	b	ReturnOp1
	
BigExp:
	// r0 = result, left justified
	// r2 = result exponent - 1
	// r3 = sticky bits
	// r7 = bit 0 is sign of result
	bge	RetInfinity
.ifdef NO_DENORMALS
	// return zero of correct sign
	lsls	r0, r7, #31	// zero with sign
	b	Exit
.else
	// r0 = result mantissa left justified
	// r2 = result exponent - 1
	// r3 = sticky bits
	// r7 = bit 0 is sign of result
	bl	__fdenormal_result
	b	SetSign
.endif

RetInfinity:
	// Build infinity
	movs	r0, #EXP_SPECIAL32
	lsls	r0, #MANT_BITS32
	b	SetSign

.ifndef NO_DENORMALS

Op2ZeroExp:
	// r0 = op1
	// r1 = op2
	// r2 = op1 exponent
	// r3 = op2 exponent
	// r5 = 0x80000000 (sign bit position)
	// r7 = sign info
	lsls	r4, r1, #1	// clear existing sign
	beq	ReturnOp1
	// op2 is denormal, so normalize it

	// __clz_denormal uses tailored calling convention
	// r4 = input to count leading zeros
	// r0 - r3, r7 preserved
	// r5, r6 trashed
	bl	__clz_denormal	// Get leading zeros in op2
	subs	r4, #EXP_BITS32
	negs	r3, r4		// op2 exponent
	adds	r4, #1
	lsls	r1, r4
	// restore r5
	movs	r5, #1
	lsls	r5, #31		// sign position
	b	Op2Normalized

Op1ZeroExp:
	// r0 = op1
	// r1 = op2
	// r2 = op1 exponent
	// r3 = op2 exponent
	// r5 = 0x80000000 (sign bit position)
	// r7 = sign info
	lsls	r4, r0, #1	// clear existing sign
	beq	ReturnOp2
	// op1 is denormal, check op2 for zero
	lsls	r6, r1, #1	// scrape off sign
	beq	ReturnOp1

	// __clz_denormal uses tailored calling convention
	// r4 = input to count leading zeros
	// r0 - r3, r7 preserved
	// r5, r6 trashed
	bl	__clz_denormal	// Get leading zeros in op1
	subs	r4, #EXP_BITS32
	negs	r2, r4		// op1 exponent
	adds	r4, #1
	lsls	r0, r4
	// restore r5
	movs	r5, #1
	lsls	r5, #31		// sign position
	b	Op1Normalized

.endif

	.endfunc
