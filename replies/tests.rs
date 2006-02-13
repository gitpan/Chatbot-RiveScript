/*
	RiveScript // Testing the various commands

	You might recognize this type of reply set from
	Chatbot::Alpha's day.
*/

/* ##############################
   ## Simple Reply Testing     ##
   ############################## */

+ test single
- This is a single reply.

+ test random
- This is random reply #1.
- This is the second random reply.
- Here is random reply #3.

/* ##############################
   ## Variables Testing        ##
   ############################## */

+ test variables
- My name is {^name}. I am {^age} years old.

// Test setting and getting a user variable
+ set name to *
- <set name={formal}<star1>{/formal}>Your name has been set to <get name>.

+ get name
- Your name is <get name>.

// Print all uservars to DOS window.
+ show vars
- Showing variables... &uservars.show()

/* ##############################
   ## Test Conditionals        ##
   ############################## */

+ is your name bob or casey
* name=Bob => I'm Bob.
* name=Casey Rive => I'm Casey.
- Neither of those are my name.

+ are you a guy or a girl
* sex=male => I'm a guy.
* sex=female => I'm a girl.
- That has yet to be determined.

/* ##############################
   ## Test Global Var Setting  ##
   ############################## */

+ test set name to bob
- {!var name = Bob}I set my name to Bob.

+ test set name to casey
- {!var name = Casey Rive}I set my name to Casey Rive.

+ test set debug on
- {!global debug = 1}Debug mode on.

+ test set debug off
- {!global debug = undef}Debug mode deactivated.

/* ##############################
   ## Test Object Macros       ##
   ############################## */

+ test object get
- Testing "get" method: &test.get()

+ test object say *
- Testing "say" method: &test.say(<star1>)

+ test object no args
- Testing object with no args: &test()

+ test void object
- Testing a void object: &void.test()

/* ##############################
   ## Wildcards Testing        ##
   ############################## */

+ test my name is *
- Nice to meet you, {formal}<star1>{/formal}.

+ * told me to say *
- Why would {formal}<star1>{/formal} tell you to say that?

/* ##############################
   ## Substitutions Testing    ##
   ############################## */

// say "I'm testing subs"
+ i am testing subs
- Did the substitution testing pass?

/* ##############################
   ## Inline Redirect Tests    ##
   ############################## */

+ test inline redirect
- If you said hello I would've said: {@hello} But if you said bye I'd say: {@bye}

+ i say *
- Indeed you do say. {@<star1>}

/* ##############################
   ## String Modify Testing    ##
   ############################## */

+ test formal odd
- {formal}this... is a test/of using odd\characters with formal.{/formal}

+ test sentence odd
- {sentence}this=/\is a test--of using odd@characters in sentence.{/sentence}

+ test uppercase
- {uppercase}this response really was lowercased at one point.{/uppercase}

+ test lowercase
- {lowercase}ThiS ORIgINal SENTence HaD CraZY CaPS iN IT!{/lowercase}

/* ##############################
   ## Long Reply Test          ##
   ############################## */

+ tell me a poem
- Little Miss Muffet,\n
^ sat on her tuffet,\n
^ in a nonchalant sort of way.\n\n
^ With her forcefield around her,\n
^ the spider, the bounder\n
^ is not in the picture today.

/* ##############################
   ## Deep Recursion Test      ##
   ############################## */

+ test recurse
@ do recurse testing

+ do recurse testing
@ test recurse

/* ##############################
   ## Test "previous"          ##
   ############################## */

+ i hate you
- You're really mean.

+ sorry
% youre really mean
- Don't worry--it's okay. ;-)

// This one stands alone.
+ sorry
- Why are you sorry?

/* ##############################
   ## Strong Redirect Test     ##
   ############################## */

+ identify yourself
- I am the RiveScript test brain.

+ who are you
@ identify yourself

/* ##############################
   ## Perl Evaluation Test     ##
   ############################## */

+ what is 2 plus 2
- 500 Internal Error.
& $reply = "2 + 2 = 4";

/* ##############################
   ## Alternation Tests        ##
   ############################## */

+ i (should|should not) do it
- You <star1> do it?

+ what (s|is) your (home|cell|work) phone number
- 555-555-5555

/* ##############################
   ## Randomness Tests         ##
   ############################## */

+ random test one
- This {random}reply trigger command{/random} has a random noun.

+ random test two
- Fortune Cookie: {random}You will be rich and famous.|You will
^ go to the moon.|You will suffer an agonizing death.{/random}

/* ##############################
   ## Test Nextreply           ##
   ############################## */

+ test nextreply
- This reply should{nextreply}appear very big{nextreply}and need 3 replies!

/* ##############################
   ## Test Input-Arrays        ##
   ############################## */

+ what color is my (@colors) *
- Your <star2> is <star1>, silly!

/* ##############################
   ## Follow-up on ^ var conc. ##
   ############################## */

+ what is your favorite quote
- "<bot quote>"

/* ##############################
   ## Test trigger conc.       ##
   ############################## */

+ how much wood would a woodchuck\s
^ chuck if a woodchuck could chuck wood
- A whole forest. ;)

+ how much wood
@ how much wood would a woodchuck\s
^ chuck if a woodchuck could chuck wood

/* ##############################
   ## Test Topics              ##
   ############################## */

+ you suck
- And you're very rude. Apologize to me now!{topic=apology}

> topic apology

	+ *
	- No, apologize.

	+ sorry
	- See, that wasn't too hard. I'll forgive you.{topic=random}
< topic