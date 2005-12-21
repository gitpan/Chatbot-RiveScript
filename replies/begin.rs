/*
	RiveScript // Begin Example

	This reply set is checked before chatting can begin.
	If it fails to return an {ok} then the brain isn't
	utilized.
*/

> begin

	// There will be a 50/50 chance he won't allow it
	+ request
	- <font color="red">{ok}</font>
//	- I'm not allowing your request right now. Try again. ;)

< begin