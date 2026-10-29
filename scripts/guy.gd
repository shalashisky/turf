extends Neighbor
## Guy: played strings on half the disco records ever cut in this town. The
## records stopped; the habit didn't. Lives over on Dummies turf, and won't
## say a word to the player while the gang holds it.


func converse(_player: Citizen) -> void:
	var turf := Territory.at(_home)
	if turf and turf.owner_faction() != Factions.PLAYER:
		await say("%s told me not to talk to you..." % Factions.short_name(turf.owner_faction()))
		return
	var pick := await choose("Hey. You're the one who ran 'em off, huh.", [
		"Give Present",
		"What's with the violin?",
		"Nevermind",
	])
	match pick:
		0:
			await give_present()
		1:
			await say("Played on every disco record in this city, man. Then the records stopped. The parties didn't.")


func nothing_to_give_line() -> String:
	return "Empty pockets, huh. Join the club."


func what_have_you_got_line() -> String:
	return "Whatcha got for an old fiddler?"


func gift_reaction_line(item: String, points: int) -> String:
	if item == "cocaine":
		return "Oh... oh, you're beautiful. Just like '78."
	if points > 0:
		return "That's real kind of you."
	if points < 0:
		return "...I can't play with this."
	return "Huh. Thanks."
