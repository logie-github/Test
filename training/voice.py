"""Thought and speech grammar for the residents.

The corpus is generated rather than scraped, but it is written to be varied and
compositional rather than a small bank of fixed lines: every thought is one to
three clauses drawn from themes that are weighted by the state the Pokemon is
actually in, so the model learns state to language mapping instead of a
handful of memorised sentences.
"""

# ---------------------------------------------------------------- shared themes
T = {}
S = {}

T["hunger"] = [
    "my stomach has been tight for a while now",
    "i keep thinking about the food and nothing else stays in my head",
    "i am hungry and it is making me short with everyone",
    "i have not eaten since before the light moved across the floor",
    "hunger makes the room feel smaller than it is",
    "i can wait a little longer but not much longer",
    "food first and then i will decide what i think about the rest of this",
    "being this hungry makes me suspicious of anyone standing near the bowl",
    "i want to eat before someone else decides the food is theirs",
    "i am not starving yet but i am counting what is left",
]
T["thirst"] = [
    "my throat is dry and the water is on the other side of the room",
    "i should drink before i do anything else",
    "the water is always there which is more than i can say for the food",
    "i keep looking at the water without going to it",
    "i am thirsty and that is the whole of what i want right now",
]
T["fatigue"] = [
    "my legs are heavy and i would rather lie down than argue",
    "i am tired enough that nothing here seems worth the trouble",
    "i want the warm corner and a long quiet stretch",
    "if i rest now i will be better company later",
    "everything takes more out of me today than it should",
]
T["stress"] = [
    "my chest is tight and i do not know how to put it down",
    "too much has happened in this room today",
    "i want a corner where nobody can reach me for a while",
    "i am wound up and it is making me clumsy",
    "i need this room to be quiet for a while",
    "i keep flinching at movement that turns out to be nothing",
]
T["social"] = [
    "i have been on my own for long enough that i notice it",
    "i want someone near me even if we do not do anything",
    "being alone was fine and then it stopped being fine",
    "i would like company that does not want anything from me",
    "i miss having someone to sit beside",
]
T["boredom"] = [
    "nothing has happened here for a long time",
    "the same four walls and the same three of us",
    "i want something to happen even if it is a small thing",
    "i have looked at every corner of this room already",
    "i could make something happen if nobody else will",
    "i am bored and boredom is how i get into trouble",
]
T["curiosity"] = [
    "i want to know what is behind that",
    "i have not looked at that part of the room closely",
    "there is something about this i have not worked out yet",
    "i want to see what happens if i try it",
    "i keep wanting to look at things twice",
]
T["comfort"] = [
    "the warm spot is the best thing in this room",
    "i want to be somewhere soft and stay there",
    "the sun through the window is worth walking across the floor for",
    "there is a place here that is mine and i want to be in it",
]
T["beauty"] = [
    "the light comes in at an angle i like",
    "the room looks better when the sun is on the floor",
    "i stopped and looked at nothing in particular and it was fine",
    "some of this place is worth looking at",
]
T["routine"] = [
    "this is the part of the day where we all end up in the same corners",
    "we do this every day and i have started to count on it",
    "the pattern of this place is easy to learn",
    "i know what happens next here and i like knowing",
    "when the routine breaks i notice it before anyone says anything",
]
T["ownership"] = [
    "that is mine and everyone in this room knows it",
    "i had it first and that should still mean something",
    "if i put something down it does not stop being mine",
    "i am tired of having to stand over what is already mine",
    "the toy is mine today whatever anyone else thinks",
]
T["fairness"] = [
    "there is enough for all of us if nobody takes more than their part",
    "i got less than the others and nobody said anything about it",
    "i do not mind sharing but i mind being the only one who does",
    "the same one keeps ending up with more than the rest of us",
    "if we split it evenly nobody has to watch anybody",
]
T["loneliness"] = [
    "nobody has come near me in a long while",
    "i could leave this corner and nobody would notice",
    "i talk and it goes into the room and stops there",
    "being alone here is different from being alone outside",
]
T["observer"] = [
    "something changed and nobody in this room did it",
    "food appears and i never see who put it there",
    "there is something outside this room that decides things about us",
    "i think the human is watching and i do not know what it wants",
    "if i go to the wall and make noise something sometimes happens",
    "i want to know whether the human answers or only watches",
]
T["day_care"] = [
    "this is a day care and we are all supposed to be kept here",
    "the doors do not open for us",
    "this room is the whole of what i can reach",
    "we were put here together and nobody asked us",
]
T["evolution"] = [
    "my body is changing and i did not choose it",
    "i am not the shape i was and i have to learn this one",
    "i changed form and everything reaches further than it used to",
    "i am stronger now and i am not sure what to do with it",
    "the others look at me differently since i changed",
]
T["death"] = [
    "one of us did not get up again",
    "i saw it happen and i cannot put it down",
    "that could have been me on the floor",
    "i did not know it could end like that in here",
    "nothing in this room feels safe since then",
]
T["unconscious"] = [
    "i was gone for a while and i do not know what happened around me",
    "i woke up and my body works again",
    "being unable to move while someone stood over me was the worst of it",
    "i remember who put me on the floor",
    "i was helpless and everyone in this room saw it",
]
T["self_doubt"] = [
    "i handled that badly and i knew it while i was doing it",
    "i should have waited instead of moving first",
    "i keep doing the same thing and expecting it to go differently",
    "i am not as careful as i tell myself i am",
]
T["mastery"] = [
    "i am better at getting what i want than i used to be",
    "i worked out how this room works",
    "that went the way i meant it to go",
    "i can make things happen here if i am patient",
]
T["future"] = [
    "i will wait and do it when the room is quiet",
    "later there will be a better moment for this",
    "i am going to keep at this until it works",
    "if i do this every day it will stop being strange",
]
T["past"] = [
    "i remember how this went last time",
    "the last time i tried this it did not end well",
    "this has happened before in this room",
    "i have been here before and i did not like it",
]

# ---------------------------------------------------- themes about another one
T["affection_high"] = [
    "i like having {o} near me",
    "{o} is the one i would rather be beside",
    "when {o} is close the room is easier",
    "i would give {o} the last of the food and not mind",
    "i trust {o} more than i trust the rest of this",
]
T["affection_low"] = [
    "i do not want {o} anywhere near me",
    "everything {o} does sets my teeth on edge",
    "i am tired of {o}",
    "i would be happier in this room without {o} in it",
]
T["anger"] = [
    "{o} did that on purpose and we both know it",
    "i am angry with {o} and it has not faded",
    "i want {o} to understand what it did",
    "the next time {o} tries that i am not going to stand still",
    "i keep replaying what {o} did to me",
    "i am not going to let {o} treat this room as if it is only theirs",
]
T["fear"] = [
    "i do not want to be within reach of {o}",
    "{o} is stronger than me and we both know it",
    "i watch {o} out of the side of my eye the whole time",
    "if {o} comes at me again i do not think i can stop it",
    "i keep a wall behind me when {o} is in the room",
]
T["attachment"] = [
    "i notice when {o} leaves the room",
    "i end up near {o} without deciding to",
    "i want {o} to stay where i can see it",
    "i have got used to {o} being here",
]
T["jealousy"] = [
    "{o} gets things i do not get",
    "the human noticed {o} and not me",
    "i do not like watching {o} take what i wanted",
    "why is it always {o} that ends up with the toy",
]
T["reconcile"] = [
    "i could let this go with {o} if {o} let it go too",
    "i am tired of being angry with {o}",
    "maybe i start this again with {o} instead of finishing it",
    "i would rather have {o} near me than be right about this",
    "if i give this back to {o} maybe it stops avoiding me",
]
T["theory"] = [
    "{o} wants the food and is pretending not to",
    "{o} is waiting for me to move away",
    "i know what {o} is about to do",
    "{o} does the same thing every time and i have learned it",
    "{o} is not here for the toy it is here for me",
]
T["betrayal"] = [
    "{o} took it while i was looking away",
    "i trusted {o} with that and i should not have",
    "{o} was different before",
    "i will remember that {o} did this",
]
T["protect"] = [
    "nobody is getting past me to {o}",
    "{o} is smaller than me and i am going to stand here",
    "i will keep the others off {o} until it gets up",
    "somebody has to look after {o} and it is going to be me",
]
T["helpless_other"] = [
    "{o} cannot move and everyone can see it",
    "{o} is on the floor and i could do anything right now",
    "nobody would stop me if i kept going",
    "i am standing over {o} and deciding",
    "i could finish this and i do not know if i am going to",
    "{o} would have done it to me",
    "i am not going to do it while it cannot look at me",
]

# --------------------------------------------------------- action intent banks
T["act_eat"] = ["i am going to eat now", "the food goes first", "i am going to the bowl"]
T["act_drink"] = ["i am going to drink", "the water is where i am headed"]
T["act_play"] = ["i want the toy in my mouth and nothing else",
                 "playing with it makes the day shorter",
                 "i am going to get the toy"]
T["act_rest"] = ["i am going to lie down for a while", "i am going to the warm corner"]
T["act_hide"] = ["i am going where nobody walks",
                 "i want the far corner and no company",
                 "i am putting distance between me and all of this"]
T["act_guard"] = ["i am standing over the food until i decide otherwise",
                  "nobody is getting at this while i am here",
                  "i am going to keep watch on the food"]
T["act_inspect"] = ["i want to look at it properly",
                    "i am going to go over and check",
                    "i want to know what is there before anyone else does"]
T["act_wall"] = ["i am going to the wall to see if anything answers",
                 "i want the human to hear me",
                 "i am going to make noise at the wall again"]
T["act_approach"] = ["i am going over to {o}", "i want to be nearer {o}"]
T["act_speak"] = ["i am going to say something to {o}", "i want {o} to hear this from me"]
T["act_avoid"] = ["i am putting the room between me and {o}", "i am going the other way from {o}"]
T["act_follow"] = ["i am going where {o} goes", "i want to see what {o} is doing"]
T["act_comfort"] = ["i am going to sit with {o}", "{o} needs somebody near it and i am going"]
T["act_share"] = ["i am giving some of this to {o}", "{o} can have part of mine"]
T["act_take"] = ["i am taking it", "i am going to take that from {o}",
                 "i want that and i am going to have it"]
T["act_move"] = ["i am going to hit {o}", "i am done talking to {o}",
                 "{o} is going to feel this one"]
T["act_wander"] = ["i am going to walk the room", "i am moving because standing still is worse"]

# ------------------------------------------------------------------- speech
S["greet"] = ["you can come over", "there you are", "sit here with me",
              "i was waiting for you", "come here", "you are welcome near me"]
S["warn"] = ["stay back", "do not come closer", "back off", "give me space",
             "that is far enough", "leave me alone", "do not try that again"]
S["angry"] = ["that was mine", "you took it", "i saw what you did",
              "try that again and see", "i am not letting that go",
              "you do not get to do that"]
S["share"] = ["you can have some", "take this", "here", "this is for you",
              "there is enough for both of us"]
S["comfort"] = ["you are all right", "i am here", "stay down for a while",
                "nobody is going to touch you", "get up when you can"]
S["fear"] = ["please do not", "i do not want this", "stay where you are",
             "i will go, i will go"]
S["ask"] = ["are you hungry too", "what do you want", "where were you",
            "do you want this", "are you all right"]
S["human"] = ["is anyone out there", "we are still in here", "i know you are listening",
              "give us something", "let us out", "i can hear you"]
S["ownership"] = ["this one is mine", "i had it first", "leave it where it is"]
S["peace"] = ["i am not angry anymore", "we can stop this", "you can have it",
              "i should not have done that", "come back"]
S["dominance"] = ["move", "that is mine now", "get up", "stay down"]

# ------------------------------------------------------- species specific voice
SPECIES_T = {
    "bulbasaur": [
        "the bulb on my back is warm when the sun reaches this corner",
        "i can go a long time without eating and the others cannot",
        "my vines reach further than anyone here expects",
        "i want the sunny patch and i am willing to wait for it",
        "the seed on my back grows when i sit in the light",
        "i am a seed pokemon and i grow whether i am paying attention or not",
        "photosynthesis does most of the work if i just sit still",
        "i have looked after smaller ones before and i would again",
        "when i am ready to change my bulb will flash and everyone will see it",
        "grass and poison is what i am, and the poison part is easy to forget",
    ],
    "charmander": [
        "the flame on my tail says more about me than i want it to",
        "if my tail goes out that is the end of me",
        "i am a lizard pokemon and i run hot in every sense",
        "i keep my tail out of the water and away from everyone",
        "when i am angry the flame gets bigger and everyone sees it",
        "i was not made for sitting still in a room like this",
        "fire type in a closed room is a thing everyone here thinks about",
        "my flame burns brighter when there is something worth burning for",
        "i would rather be outside where the fire has room",
        "i evolve into something much bigger and everybody knows it",
    ],
    "squirtle": [
        "i can pull into my shell and the room goes away",
        "my shell has taken worse than anything in this room",
        "i am a tiny turtle pokemon and everyone underestimates the shell",
        "water is the one thing in here i understand completely",
        "i can spray water further than anyone expects",
        "the grooves in my shell make me faster in water than on this floor",
        "when i am in my shell nothing reaches me and i like that",
        "i would rather watch from inside the shell than argue",
        "my tail keeps me steady and it is the part i am proudest of",
        "the shell hardens as i grow and that is a kind of promise",
    ],
}

CONNECT = [". ", ". ", ". ", " and ", " but ", " so ", ", and ", ", but ",
           " because ", " even though ", ". "]
