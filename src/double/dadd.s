
/*
 * dadd.s
 *
 * Created: 9/17/2021
 *  Author: Tim
 */

.syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"
.include "ieee.inc"
.include "options.inc"

	.global	__dadd_saved

// 64-bit IEEE floating-point add
//
// Entry:
//	r1:r0 = op1
//	r3:r2 = op2
// Exit:
//	r1:r0 = op1 + op2

	.func	__dadd

.ifdef NO_DENORMALS

.set	Op2ZeroExp, ReturnOp1
.set	Op1ZeroExp, ReturnOp2

.else

Op2ZeroExp:
	// r1:r0 = op1
	// r3:r2 = op2
	// r4 = op1 exponent
	// r5 = op2 exponent (zero)
	// r7 = bit 0 = sign of op1, bit 31 = sign xor
	lsls	r6, r3, #1	// clear existing sign
	orrs	r6, r2
	beq	ReturnOp1	// op2 is zero, return op1
	// __dop2_normalize uses tailored calling convention
	// input: r3:r2 = op2
	// returns r5 = op2 exponent (< 0)
	// all other registers preserved
	bl	__dop2_normalize
	str	r2, [sp]	// update pushed r2, might be needed
	b	Op2Normalized

Op1ZeroExp:
	// r1:r0 = op1
	// r3:r2 = op2
	// r4 = op1 exponent (zero)
	// r7 = bit 0 = sign of op1, bit 31 = sign xor
	lsls	r5, r1, #1	// clear existing sign
	orrs	r5, r0
	beq	ReturnOp2	// op1 is zero, return op2
	// op1 is denormal, check op2 for zero
	lsls	r5, r3, #1	// scrape off sign
	orrs	r5, r2
	beq	ReturnOp1	// op2 is zero, return op1
	// __dop1_normalize uses tailored calling convention
	// input: r1:r0 = op1
	// returns r4 = op1 exponent (< 0)
	// r5 trashed
	// all other registers preserved
	bl	__dop1_normalize
	b	Op1Normalized

.endif

ENTRY_POINT	__dadd, __aeabi_dadd
	push	{r2, r4-r7, lr}	// must match __dsub & __drsub, which enter next
__dadd_saved:
	lsrs	r7, r1, #31	// grab sign of op1
	lsrs	r4, r3, #31	// sign of op2
	eors	r4, r7		// see if signs the same
	lsls	r4, #31		// back to sign position
	orrs	r7, r4		// combine sign info

	lsls	r4, r1, #1	// clear op1 sign
	lsrs	r4, #MANT_BITS_HI64 + 1	// op1 exponent
	beq	Op1ZeroExp
Op1Normalized:
	lsls	r5, r3, #1	// clear op2 sign
	lsrs	r5, #MANT_BITS_HI64 + 1	// op2 exponent
	beq	Op2ZeroExp
Op2Normalized:
	ldr	r6, =#EXP_SPECIAL64 - 1
	mov	lr, r6
	cmp	r5, lr
	bgt	Op2SpclExp
	// If op1 is special (and op2 not), just return op1
	cmp	r4, lr
	bgt	ReturnOp1

	// r1:r0 = op1
	// r3:r2 = op2
	// r4 = op1 exponent
	// r5 = op2 exponent
	// r7 = bit 0 = sign of op1, bit 31 = sign xor
	// lr = max allowed exponent

	// Clear exponent, set implied bit
	movs	r6, #1
	lsls	r6, #31		// sign position
	lsls	r1, #EXP_BITS64
	lsls	r3, #EXP_BITS64
	orrs	r1, r6
	orrs	r3, r6
	lsrs	r1, #EXP_BITS64
	lsrs	r3, #EXP_BITS64

	subs	r6, r4, r5	// op1 exp - op2 exp
	bmi	Op2Larger
	// op1 is larger (or same)
	mov	r12, r4		// save exponent
	subs	r6, #32
	bhi	LongOp2Shift
	negs	r5, r6		// no. of bits to shift off for sticky bits
	adds	r6, #32
	// 64-bit right shift of r3:r2
	movs	r4, r3
	lsls	r4, r5
	lsrs	r3, r6
	lsrs	r2, r6
	orrs	r2, r4
	ldr	r4, [sp]	// recover original low half of op2
	lsls	r4, r5		// round & sticky bits for what we're shifting off
CheckSign:
	orrs	r7, r7		// check sign flags
	bmi	SubOp2		// signs were different, subtract
AddOps:
	// signs are the same, add operands
	// r1:r0 = op1 mantissa
	// r3:r2 = op2 mantissa, aligned to match op1 exponent
	// r4 = sticky bits
	// r7 = bit 0 is sign of result
	// r12 = result exponent
	// lr = max allowed exponent
	adds	r0, r2		// sum it
	adcs	r1, r3
	mov	r2, r12		// bring back exponent
	// See if carried into the next bit
	lsls	r5, r1, #EXP_BITS64
	bcs	AddOverflow
Round:
	// r1:r0 = result
	// r2 = result exponent
	// r4 = sticky bits
	// r7 = bit 0 is sign of result
	// lr = max allowed exponent
.ifndef	NO_DENORMALS
	cmp	r2, #0
	ble	TinyExp
.endif
	lsls	r5, r4, #1	// rounding bit to CY
	bcc	NoRound		// no rounding bit
	bne	RoundUp		// have rounding bit and sticky bits
RoundEven:
	// Have rounding bit but no sticky bits, so round even
	lsrs	r5, r0, #1	// LSB to CY
	bcc	NoRound		// already even
RoundUp:
	movs	r3, #0
	adds	r0, #1		// add to rounding bit
	adcs	r1, r3
NoRound:
	subs	r2, #1		// adjust for adding implied bit
	lsls	r2, #MANT_BITS_HI64
	adds	r1, r2
SetSign:
	lsls	r7, #31
	adds	r1, r7
Exit:
	pop	{r2, r4-r7, pc}

ReturnOp2:
	movs	r0, r2
	movs	r1, r3
ReturnOp1:
	pop	{r2, r4-r7, pc}

Op2SpclExp:
	// r1:r0 = op1
	// r3:r2 = op2
	// r4 = op1 exponent
	// r5 = op2 exponent
	// r6 = 0x80000000 (sign bit position)
	// r7 = bit 0 = sign of op1, bit 31 = sign xor
	// lr = max allowed exponent
	//
	// op2 mantissa == 0?
	lsls	r6, r3, #(EXP_BITS64 + 1)
	orrs	r6, r2
	bne	ReturnOp2	// op2 is NAN, return it
	// op2 is Infinity
	// if (expOp1 == EXP_SPECIAL)
	cmp	r4, lr
	ble	ReturnOp2	// op1 not special, return op2
	// op1 mantissa == 0?
	lsls	r6, r1, #(EXP_BITS64 + 1)
	orrs	r6, r0
	bne	ReturnOp1	// op1 is NAN, return it
	// Both op1 & op2 are infinity. If signs differ, return NAN
	eors	r3, r1
	bpl	ReturnOp1	// signs the same, return infinity
	// return NAN
	ldr	r1, =#NAN64
	movs	r0, #0
	b	ReturnOp1
	
Op2Larger:	
	// r1:r0 = op1 mantissa
	// r3:r2 = op2 mantissa
	// r4 = op1 exponent
	// r5 = op2 exponent
	// r6 = exponent difference (< 0)
	// r7 = bit 0 = sign of op1, bit 31 = sign xor
	// lr = max allowed exponent
	//
	// op2 has a larger exponent, so it's bigger for sure
	mov	r12, r5		// save exponent
	negs	r5, r6
	adds	r6, #32
	bmi	LongOp1Shift
	// 64-bit right shift of r1:r0
	// r2 was saved on entry so can be used as temp
	movs	r4, r0
	movs	r2, r1
	lsls	r2, r6
	lsrs	r1, r5
	lsrs	r0, r5
	orrs	r0, r2
	lsls	r4, r6		// round & sticky bits for what we're shifting off
	ldr	r2, [sp]	// recover original r2
Op2CheckSign:
	orrs	r7, r7		// check sign flags
	bpl	AddOps
	// op2 - op1
	adds	r7, #1		// flip sign bit in LSB
	negs	r4, r4		// 0 - sticky bits
	sbcs	r2, r0
	sbcs	r3, r1
	movs	r0, r2
	movs	r1, r3
	b	Normalize

LongOp2Shift:
	// r1:r0 = op1 mantissa
	// r3:r2 = op2 mantissa
	// r6 = exp1 - exp2 - 32 (> 0)
	// r7 = bit 0 = sign of op1, bit 31 = sign xor
	// r12 = result exponent
	// lr = max allowed exponent
	cmp	r6, #MANT_BITS_HI64 + 3	// include implied, round & sticky bits
	bhi	UseOp1
	negs	r5, r6
	adds	r5, #32		// r5 = 32 - r6
	// keep round & sticky bits for what we're shifting off
	movs	r4, r2
	lsrs	r4, r6
	lsls	r2, r5
	beq	1f
	orrs	r4, r3		// non-zero value that doesn't touch rounding bit
1:
	movs	r2, r3
	lsrs	r2, r6
	lsls	r3, r5
	orrs	r4, r3
	movs	r3, #0
	b	CheckSign

AddOverflow:
	cmp	r2, lr		// lr = EXP_SPECIAL64 - 1
	beq	RetInfinity
.ifndef	NO_DENORMALS
	bhi	TinyExp
.endif
	adds	r2, #1		// adjust exponent
	// shift right 1 bit
	lsls	r3, r1, #31
	lsrs	r1, #1
	lsrs	r0, #1		// CY = rounding bit
	add	r0, r3		// combine without affecting flags
	bcc	NoRound
	cmp	r4, #0
	bne	RoundUp
	b	RoundEven

SubOp2:
	// op1 - op2
	// However, it could be op1 <= op2 with same exponent
	negs	r4, r4		// 0 - sticky bits
	sbcs	r0, r2
	sbcs	r1, r3
	bpl	Normalize
	// Subtracted wrong way.
	adds	r7, #1		// flip sign bit in LSB
	movs	r3, #0
	mvns	r1, r1
	negs	r0, r0
	adcs	r1, r3
Normalize:
	// flags set according to r1
	mov	r2, r12		// bring back exponent, flags not affected
	bne	HaveBits	// r1 not zero
	orrs	r1, r0
	orrs	r1, r4
	beq	Exit		// return zero result
NormWord:
	// shift in bits from r0
	subs	r2, #MANT_BITS_HI64 + 1
	lsrs	r1, r0, #31 - MANT_BITS_HI64
	lsls	r0, #MANT_BITS_HI64 + 1
	lsrs	r5, r4, #31 - MANT_BITS_HI64
	orrs	r0, r5
	lsls	r4, #MANT_BITS_HI64 + 1
	cmp	r1, #0
	beq	NormWord
HaveBits:
	lsls	r5, r1, #EXP_BITS64 + 1	// shift normalization bit into CY
	bcs	Round
	movs	r3, #0		// shift counter
	// Check for big chunks of leading zeros
	// These checks need to leave at least 1 leading zero
	// for the final step.
.set	NORM,	5
	lsrs	r6, r5, #32 - NORM
	bne	NormLoop
LongNorm:
	adds	r3, #NORM	// count
	lsls	r5, #NORM	// normalize a bunch
	lsrs	r6, r5, #32 - NORM
	beq	LongNorm
	// Finish off bit-by-bit
NormLoop:
	adds	r3, #1		// count bits to shift
	lsls	r5, #1		// normalize one bit
	bcc	NormLoop
	// Shift result in r1:r0:r4 left by count in r3
	movs	r5, r0
	lsls	r1, r3
	lsls	r0, r3
	negs	r6, r3
	adds	r6, #32
	lsrs	r5, r6
	orrs	r1, r5
	movs	r5, r4
	lsrs	r5, r6
	orrs	r0, r5
	lsls	r4, r3
	subs	r2, r3		// adjust exponent
	bgt	Round
TinyExp:

.ifdef NO_DENORMALS
	// return zero of correct sign
	movs	r0, #0
	lsls	r1, r7, #31	// zero with sign
	pop	{r2, r4-r7, pc}
.else
	// r1:r0 = result mantissa
	// r2 = result exponent
	// r4 = sticky bits
	// r7 = sign in LSB
	subs	r2, #1		// helper needs exponent - 1
	bl	__ddenormal_result
	b	SetSign
.endif

LongOp1Shift:
	// r1:r0 = op1 mantissa
	// r3:r2 = op2 mantissa
	// r5 = exp2 - exp1 (> 32)
	// r6 = exp1 - exp2 + 32 (< 0)
	// r7 = bit 0 = sign of op1, bit 31 = sign xor
	// r12 = result exponent
	// lr = max allowed exponent
	cmp	r5, #MANT_BITS64 + 3	// include implied, round & sticky bits
	bhi	UseOp2
	subs	r5, #32		// r5 = right shift count
	adds	r6, #32		// r6 = 32 - r5
	// keep round & sticky bits for what we're shifting off
	movs	r4, r0
	lsrs	r4, r5
	lsls	r0, r6
	beq	1f
	orrs	r4, r1		// non-zero value that doesn't touch rounding bit
1:
	movs	r0, r1
	lsrs	r0, r5
	lsls	r1, r6
	orrs	r4, r1
	movs	r1, #0
	b	Op2CheckSign

UseOp2:
	movs	r0, r2
	movs	r1, r3
	lsrs	r5, r7, #31	// xor of signs to LSB
	eors	r7, r5		// sign of op2
UseOp1:
	mov	r2, r12		// bring back exponent
	b	NoRound

RetInfinity:
	// return infinity
	ldr	r1, =#INFINITY64
	movs	r0, #0
	b	SetSign

	.endfunc
