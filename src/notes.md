## Value semantics vs Reference Semantics
### object vs. ref object (https://forum.nim-lang.org/t/1207)
	The primary between a plain object and a reference is that assignment makes a copy of the original object. This makes having shared state harder (aside from objects that are declared in a local or global variable and are passed around exclusively using var parameters). It also creates significant overhead for assigning large objects (since the entire state has to be copied).
	Another important difference is that plain objects and polymorphism do not mix well. Anything you assign an object of a subtype to a variable of a supertype, any extraneous state that only exists in the subtype has to be stripped.
	What Jehan said can be illustrated in an example like so:

	```
	type
		rob = ref ob
		ob = object
			key: int

	var ob1 = ob(key:42)
	var ob2 = ob1 # makes a copy of ob1
	ob2.key = 2

	echo ob1.key # prints 42
	echo ob2.key # prints 2


	var rob1 = rob(key:42)
	var rob2 = rob1 # rob2 now points to rob1

	rob2.key = 2

	echo rob1.key # prints 2
	echo rob2.key # prints 2
	```
	
	Always prefer the syntax student = Student(name: "Anton", age: 5, id: 2) over new. new makes it much harder for the compiler to prove a complete initialization is done. The optimizer will also soon take advantage of this fact. (https://forum.nim-lang.org/t/3870)
	
	As a summary, object types are equivalent to C structs, while references types are somewhat equivalent to C pointers (but safer).
	Objects are stored on the stack or directly within the memory allocated for another object, while references always point to memory allocated on the heap (and never memory within the bounds of another block of reference memory). (https://forum.nim-lang.org/t/2909)
	
	A sequence is already a reference type. Just remember: writing ref seq[Node[T]] never makes sense, it's simply redundant.
	n.b. seq is implemented as a pointer, but it has value semantics.
		```
		var a = @[1,2,3]
		var b = a # b is now a new copy of a
		```


	The Nim compiler is smart enough to decide when to pass by reference or pass by value even though there is no var modifer. The compiler will calculate the object/tuple size, and if it exceeds a certain limit, it will be pass by reference, otherwise pass by value. The var modifier will force it to pass by reference,  semantically it means "mutable".
	With "ref object", you can modify the object value with or without "var". But the meaning of the var modifier is still the same: with "var", you can alter the reference value -> the variable point to another object. while without you cannot, although you can modify the object pointed by the reference. (https://forum.nim-lang.org/t/3869)
	
	Value objects can be considered fixed-size named memory regions, where their quantity is known at compile time. But when we need many instances of an object, whose quantity is not known in advance, then references (ref objects) allow the creation of many instances at run time, with new() or similar allocation procs. Needed for example for tree like data structures or similar dynamic data.


	Under the hood, ref smth implies heap allocation and an extra access indirection. Heap allocation is more expensive than stack allocation, so it might matter in performance critical code paths. But then again, refs are generally faster to assign to each other, as they take up a single machine word. 
	
	
	A few traits of references/pointers are: 
		-Nilable by default	
		-Heap allocated	
		-Can use methods/OOP inheritance	
		-Do not copy on assignment	
		-In parameters `var ref T` is mutable and can be reassigned, but `ref T`cannot be, but it's held values/fields are still mutable (without strict funcs)	
		-Pointer indirection, when storing a reference objects contigiously there is no guarantee the pointed at values are held contigiously.	

	Compared to objects traits:
		-Safe initalized value by default	
		-Generally stack allocated	
		-Can use inheritance only to copy fields, otherwise you use tagged unions to replicate OOP inheritance	
		-Generally copies on assignment(unless using move semantics)	
		-In parameters `T` is immutable and `var T` is required to mutate unless using unsafe code and the object is passed as a reference	
		-Collections store the actual structs contigiously which aides performance through cache efficiency
	https://forum.nim-lang.org/t/8426
	
	if we insert it (ref object) into a data structure only the reference to the object is inserted (https://peterme.net/nim-types-originally-a-reddit-reply.html)