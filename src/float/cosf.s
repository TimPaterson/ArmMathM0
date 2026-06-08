
/*
 * cosf.s
 *
 * Created: 6/22/2023 9:52:01 AM
 *  Author: Tim
 */

.syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"
.include "ieee.inc"
.include "trigf.inc"


//****************************************************************************
// 32-bit floating-point cosine
//
// Entry:
//	r0 = input angle in radians
// Exit:
//	r0 = cosine
//
// This simply calls __sincosf_calc, which returns sinf() in r0 and cosf() in r1.
//****************************************************************************


FUNC_START	__cosfM0, cosf
	push	{r4-r7, lr}
	lsls	r1, r0, #1		// clear input sign
	lsrs	r1, #MANT_BITS32 + 1	// isolate exponent
	cmp	r1, #SINE_MAX_VALID_EXP + EXP_BIAS32
	bgt	BigExp
	cmp	r1, #COS_X_EQUALS_1_EXP + EXP_BIAS32
	blt	ReturnOne		// result = 1.0

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

	// check whether to swap sin/cos
	adds	r3, r6, 1	// add to octant bit 0
	lsrs	r3, #2		// octant bit 1 to CY
	bcs	1f
	movs	r0, r1		// use cos instead of sin
	movs	r4, r5
1:
	negs	r2, r4
	adds	r2, EXP_BIAS32 - 1
	adds	r6, #2		// add to octant bit 1
	lsrs	r6, #2		// isolate octant bit 2
	lsls	r6, #31		// sign bit
	lsls	r2, #MANT_BITS32// position exponent
	lsrs	r0, #EXP_BITS32	// position mantissa
	adcs	r0, r2		// combine exponent and rounding bit
	orrs	r0, r6		// include sign
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
	pop	{r4-r7, pc}

ReturnOne:
	MOV_IMM	r0, ONE32
	pop	{r4-r7, pc}

.endfunc
