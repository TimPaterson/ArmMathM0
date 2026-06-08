
/*
 * sincosf.s
 *
 * Created: 6/22/2023 9:57:54 AM
 *  Author: Tim
 */

.syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"
.include "ieee.inc"
.include "trigf.inc"


//****************************************************************************
// 32-bit floating-point sine & cosine
//
// Entry:
//	r0 = input angle in radians
//	r1 = pointer to location to store sin()
//	r2 = pointer to location to store cos()
// Exit:
//	None.
//
// This simply calls __sincosf_calc, which returns sinf() in r0 and cosf() in r1.
//****************************************************************************


FUNC_START	__sincosfM0, sincosf
	push	{r1,r2,r4-r7, lr}
	lsls	r1, r0, #1		// clear input sign
	lsrs	r1, #MANT_BITS32 + 1	// isolate exponent
	cmp	r1, #SINE_MAX_VALID_EXP + EXP_BIAS32
	bgt	BigExp
	cmp	r1, #COS_X_EQUALS_1_EXP + EXP_BIAS32
	blt	SmallOp

	// r0 = input angle in radians
	// r1 = biased exponent e, COS_X_EQUALS_1_EXP < e < SINE_MAX_VALID_EXP

	bl	__sincosf_calc

	// r0 = sine p31
	// r1 = cosine p31
	// r4 = -exponent of sine
	// r5 = -exponent of cosine
	// r6 = octant info

	// Bits 0-2: octant number
	//  octant  |  swap | sin | cos | tan
	//     0    |    no |  +  |  +	|  +
	//     1    |   yes |  +  |  +	|  +
	//     2    |   yes |  +  |  -	|  -
	//     3    |    no |  +  |  -	|  -
	//     4    |    no |  -  |  -	|  +
	//     5    |   yes |  -  |  -	|  +
	//     6    |   yes |  -  |  +	|  -
	//     7    |    no |  -  |  +	|  -
	//		  ^    ^     ^	   ^
	// (octant+1) & 2 |    |     |	   |
	//	    octant & 4 |     |	   |
	//	      (octant+2) & 4 |	   |
	//			octant & 2 |

	// combine sine
	negs	r2, r4
	adds	r2, EXP_BIAS32 - 1
	lsls	r2, #MANT_BITS32// position exponent
	lsrs	r0, #EXP_BITS32	// position mantissa
	adcs	r0, r2		// combine exponent and rounding bit
	lsrs	r4, r6, #2	// isolate octant bit 2
	lsls	r4, #31		// sign bit

	// combine cosine
	negs	r2, r5
	adds	r2, EXP_BIAS32 - 1
	lsls	r2, #MANT_BITS32// position exponent
	lsrs	r1, #EXP_BITS32	// position mantissa
	adcs	r1, r2		// combine exponent and rounding bit
	adds	r5, r6, #2	// add to octant bit 1
	lsrs	r5, #2		// isolate octant bit 2
	lsls	r5, #31		// sign bit

	// check whether to swap sin/cos
	pop	{r2, r3}
	adds	r6, 1		// add to octant bit 0
	lsrs	r6, #2		// octant bit 1 to CY
	bcc	SetSign
	orrs	r1, r4		// include sign
	orrs	r0, r5		// include sign
	str	r1, [r2]
	str	r0, [r3]
	pop	{r4-r7, pc}

SetSign:
	orrs	r0, r4		// include sign
	orrs	r1, r5		// include sign
Save:
	str	r0, [r2]
	str	r1, [r3]
	pop	{r4-r7, pc}


BigExp:
	cmp	r1, #EXP_SPECIAL32
	bne	ReturnNan	// Huge, can't do it, return NAN
	// If argument is NAN, return it. If it's infinity, make a new NAN.
	lsls	r2, r0, #(EXP_BITS32 + 1)	// mantissa == 0?
	bne	ReturnOp	// input is NAN, return it
ReturnNan:
	MOV_IMM	r0, NAN32
ReturnOp:
	movs	r1, r0
	b	PopSave

SmallOp:
	// return r0 as-is for sine
	// return 1.0 for cosine
	MOV_IMM	r1, ONE32
PopSave:
	pop	{r2, r3}
	b	Save

.endfunc
