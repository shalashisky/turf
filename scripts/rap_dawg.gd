extends Neighbor
## Rap Dawg: the king of rap when you were a kid. These days, a washed-up
## neighbor in a faded beanie.


func converse(_player: Citizen) -> void:
	var pick := await choose("Hey man", [
		"Give Present",
		"What happened to you? You were the king of rap when I was a kid",
		"Nevermind",
	])
	match pick:
		0:
			await give_present()
		1:
			await say("I stopped believing")


func nothing_to_give_line() -> String:
	return "You ain't got nothin', man."


func what_have_you_got_line() -> String:
	return "Whatchu got?"


func gift_reaction_line(_item: String, points: int) -> String:
	if points > 0:
		return "Oh, man... maybe I gotta believe again."
	if points < 0:
		return "...What am I supposed to do with this?"
	return "Uh. Thanks, I guess."
