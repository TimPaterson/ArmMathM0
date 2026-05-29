//****************************************************************************
// logtablef.s
//
// Created 5/23/2026 6:11:11 PM by Tim Paterson
//
//****************************************************************************

.syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"


	.global	__logtablef

//****************************************************************************
// Table on natural logarithms for 1 + 2^-n, 1 <= n <= 15, p32
//****************************************************************************

__logtablef:
	.word	0x67CC8FB3
	.word	0x391FEF8F
	.word	0x1E27076E
	.word	0x0F851860
	.word	0x07E0A6C4
	.word	0x03F81516
	.word	0x01FE02A7
	.word	0x00FF8055
	.word	0x007FE00B
	.word	0x003FF801
	.word	0x001FFE00
	.word	0x000FFF80
	.word	0x0007FFE0
	.word	0x0003FFF8
	.word	0x0001FFFE
	.word	0x00010000
	.word	0x00008000
	.word	0x00004000
	.word	0x00002000
	.word	0x00001000
