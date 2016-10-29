--This library is free software; you can redistribute it and/or
--modify it under the terms of the GNU Lesser General Public
--License as published by the Free Software Foundation; either
--version 2.1 of the License, or (at your option) any later version.

stonemakelight={}
stonemakelight.vote_needed=8;  --needed votes
stonemakelight.formspec_buffer={}
stonemakelight.candidate_by_name={}

stonemakelight.mute_by_name={}	--player name => sheriff name

stonemakelight.filename = minetest.get_worldpath() .. "/stonemakelight_by_name.txt"

function stonemakelight:save()
    local datastring = minetest.serialize(self.candidate_by_name)
    if not datastring then
        return
    end
    local file, err = io.open(self.filename, "w")
    if err then
        return
    end
    file:write(datastring)
    file:close()
end

function stonemakelight:load()
    local file, err = io.open(self.filename, "r")
    if err then
        self.candidate_by_name = {}
        return
    end
    self.candidate_by_name = minetest.deserialize(file:read("*all"))
    if type(self.candidate_by_name) ~= "table" then
        self.candidate_by_name = {}
    end
    file:close()
end

stonemakelight:load();

--every restart - decrease vote result
--also allows people to vote again
for key, val in pairs(stonemakelight.candidate_by_name) do
	val.ip_voters={}
    if val.votes > 30 then
        val.votes = val.votes - math.floor(val.votes/10);   -- 10% off to prevent creation of "untouchable" sheriff
    elseif val.votes < -30 then
        val.votes = val.votes + math.floor(math.abs(val.votes)/10);  --at least a little hope to not be demoted eternally
    elseif val.votes > 0 then
        val.votes = val.votes - 1;
    elseif val.votes < 0 then
        val.votes = val.votes + 1;
	else
		stonemakelight.candidate_by_name[key] = nil;
    end
	
end

--this was modified first to create the sun altar, found out later what I needed to edit
stonemakelight.after_place_node = function(pos, placer, itemstack)
    if placer and placer:is_player() and itemstack:get_name()=="paucity:emptymoney" then
		itemstack:take_item();
        local node = minetest.get_node(pos);
        local meta = minetest.get_meta(pos);
        local description = "If you use 1 emptymoney here it will become day!";
        local player_name = placer:get_player_name();
        meta:set_string("infotext", description);
        meta:set_string("owner", player_name);
        meta:set_string("formspec", "size[6,3;]"
            .."label[0,0;Write player name to vote sheriff:]"
            .."field[1,1;3,1;candidate;;]"
            .."button_exit[0,2;2,0.5;save;OK]");
    end
end

stonemakelight.receive_config_fields = function(pos, formname, fields, sender)
    local node = minetest.get_node(pos);
    local meta = minetest.get_meta(pos);
    local candidate_name = tostring(fields.candidate);
    local player_name = sender:get_player_name();
    local description = "Vote for <".. candidate_name .."> to become sheriff until the end of the day. Tap or click with emptymoney to vote.";
    if fields.candidate and player_name and candidate_name~="" then
        meta:set_string("infotext", description);
        meta:set_string("owner", nil);
        meta:set_string("formspec", nil);
        meta:set_string("candidate", candidate_name);
        stonemakelight.register_vote(player_name, candidate_name, pos);
    end
end

-- Here's where I added minetest.set_timeofday
stonemakelight.on_rightclick = function(pos, node, player, itemstack, pointed_thing)
    local meta = minetest.get_meta(pos);
    local candidate_name = meta:get_string("candidate");
    local player_name = player:get_player_name();
    if itemstack:get_name()=="paucity:emptymoney" then
		itemstack:take_item();
		minetest.set_timeofday(0.208)
		minetest.chat_send_all("<"..player_name.."> activated the sun altar(price: 1 emptymoney)");
		minetest.log("action", "<"..player_name.."> activated the sun altar ");
		

    elseif candidate_name then
        minetest.chat_send_player(player_name, "Use 1 paucity:emptymoney to activate the sun altar. (it will be consumed)");
    end
end

stonemakelight.on_voting = function(player, formname, fields)
    if formname=="stonemakelight:vote" and player:is_player() then
        local player_name = player:get_player_name();
        local candidate_name = stonemakelight.formspec_buffer[player_name].candidate;
        local player_ip = minetest.get_player_ip( player_name );
        if candidate_name and stonemakelight.candidate_by_name[candidate_name].ip_voters[player_ip] then
            local votes_result = stonemakelight.candidate_by_name[candidate_name].votes;
            minetest.chat_send_player( player_name, "Already voted! Result:"..votes_result.." of ".. stonemakelight.vote_needed );
        elseif candidate_name and stonemakelight.candidate_by_name[candidate_name] then
            if fields.confirm then
                stonemakelight.candidate_by_name[candidate_name].ip_voters[player_ip] = "voted";
                
                local votes_result = stonemakelight.candidate_by_name[candidate_name].votes + 1;
                stonemakelight.candidate_by_name[candidate_name].votes = votes_result;
                minetest.chat_send_all("Voted by <"..player_name.."> to  promote <"..candidate_name..">. Result:"..votes_result.." of ".. stonemakelight.vote_needed);
                minetest.log("action", "Voted by <"..player_name.."> to  promote <"..candidate_name..">. Result:"..votes_result.." of ".. stonemakelight.vote_needed);
                if votes_result == stonemakelight.vote_needed then
                    minetest.chat_send_all("Player <"..candidate_name.."> now has sheriff powers." );
                end
            elseif fields.cancel then
                stonemakelight.candidate_by_name[candidate_name].ip_voters[player_ip] = "voted";
                
                local votes_result = stonemakelight.candidate_by_name[candidate_name].votes - 1;
                stonemakelight.candidate_by_name[candidate_name].votes = votes_result;
                minetest.chat_send_all("Voted by <"..player_name.."> to demote <"..candidate_name..">. Result:"..votes_result.." of ".. stonemakelight.vote_needed);
                minetest.log("action", "Voted by <"..player_name.."> to demote <"..candidate_name..">. Result:"..votes_result.." of ".. stonemakelight.vote_needed);
                if votes_result == (stonemakelight.vote_needed-1) then
                    minetest.chat_send_all("Player <"..candidate_name.."> is no longer sheriff." );
                    
                    --Unmute all victims of old sheriff
                    for key, val in pairs(stonemakelight.mute_by_name) do
                        if val == candidate_name then
                            stonemakelight.mute_by_name[key] = nil;
                        end
                    end
                    
                end
            elseif fields.cancel2 then
                stonemakelight.candidate_by_name[candidate_name].ip_voters[player_ip] = "voted";
                
                local votes_result = stonemakelight.candidate_by_name[candidate_name].votes - 1;
                stonemakelight.candidate_by_name[candidate_name].votes = votes_result;
                minetest.chat_send_all("Voted by scared player to demote <"..candidate_name..">. Result:"..votes_result.." of ".. stonemakelight.vote_needed);
                minetest.log("action", "Voted by <"..player_name.."> to demote <"..candidate_name..">. Result:"..votes_result.." of ".. stonemakelight.vote_needed);
                if votes_result == (stonemakelight.vote_needed-1) then
                    minetest.chat_send_all("Player <"..candidate_name.."> is no longer sheriff." );
                    
                    --Unmute all victims of old sheriff
                    for key, val in pairs(stonemakelight.mute_by_name) do
                        if val == candidate_name then
                            stonemakelight.mute_by_name[key] = nil;
                        end
                    end
                    
                end
            end
            stonemakelight:save();
        end
    end
end

stonemakelight.register_vote = function(player_name, candidate_name, pos)
    if candidate_name then
        if not stonemakelight.candidate_by_name[candidate_name] then
            stonemakelight.candidate_by_name[candidate_name]={};
            stonemakelight.candidate_by_name[candidate_name].votes=0;
            stonemakelight.candidate_by_name[candidate_name].ip_voters={};
			stonemakelight.candidate_by_name[candidate_name].action_delay=0;
        end
		minetest.chat_send_all("It is now morning");
    end
end

stonemakelight.vote = function(player_name, candidate_name)

end

stonemakelight.unvote = function(player_name, candidate_name)

end

minetest.register_on_player_receive_fields( stonemakelight.on_voting );

minetest.register_node("stonemakelight:table", {
	description = "sun altar",
	tiles = {"stonemakelight_top.png", "stonemakelight.png"},
	is_ground_content = false,
	groups = {choppy=2,dig_immediate=2},
    is_ground_content = false,
    after_place_node = stonemakelight.after_place_node,
    on_receive_fields = stonemakelight.receive_config_fields,
    on_rightclick = stonemakelight.on_rightclick,
});

--And here is how sheriff powers are working
minetest.register_chatcommand("mute", {
	params = "<playername>",
	description = "Forbid players to write in chat. Elected Sheriff can use this command.",
	func = function(sheriffname, playername)
		if playername and sheriffname and stonemakelight.candidate_by_name[sheriffname] then
			if stonemakelight.candidate_by_name[sheriffname].votes >= stonemakelight.vote_needed then
				stonemakelight.mute_by_name[playername] = sheriffname;
				minetest.chat_send_all("Sheriff <"..sheriffname.."> muted player <"..playername..">.");
				minetest.log("action", "Sheriff <"..sheriffname.."> muted player <"..playername..">.");
			else
				minetest.chat_send_player(sheriffname, "You are not elected as sheriff.");
			end
		end
	end,
})

minetest.register_chatcommand("unmute", {
	params = "<playername>",
	description = "Allow players to write in chat. Elected Sheriff can use this command.",
	func = function(sheriffname, playername)
		if playername and sheriffname and stonemakelight.candidate_by_name[sheriffname] then
			if stonemakelight.candidate_by_name[sheriffname].votes >= stonemakelight.vote_needed then
				stonemakelight.mute_by_name[playername] = nil;
				minetest.chat_send_all("Sheriff <"..sheriffname.."> unmuted player <"..playername..">.");
				minetest.log("action", "Sheriff <"..sheriffname.."> unmuted player <"..playername..">.");
			else
				minetest.chat_send_player(sheriffname, "You are not elected as sheriff.");
			end
		end
	end,
})

minetest.register_on_chat_message(function(playername, message)
	if stonemakelight.mute_by_name[playername] then
		minetest.chat_send_player(playername, "Sheriff <"..stonemakelight.mute_by_name[playername].."> muted you until server restart or sheriff is demoted.");
		return true	--prevent message
	end
end)

minetest.register_chatcommand("jail", {
	params = "<playername>",
	description = "Send specified player to jail. Only elected Sheriff with at least "..(stonemakelight.vote_needed*2).." votes can use this command.",
	func = function(sheriffname, playername)
		if playername and sheriffname and stonemakelight.candidate_by_name[sheriffname] then
			if stonemakelight.candidate_by_name[sheriffname].votes >= stonemakelight.vote_needed*2 then
				if stonemakelight.candidate_by_name[sheriffname].action_delay < 1 then
                    local suspect = minetest.get_player_by_name(playername);
                    if suspect then
                        suspect:setpos( {x=0, y=-2, z=0} );
                        minetest.chat_send_player(playername, "Sheriff <"..sheriffname.."> jailed player <"..playername..">. If you think this is wrong, then ask help from other players to demote sheriff.");
                        minetest.chat_send_all("Sheriff <"..sheriffname.."> jailed player <"..playername..">.");
                        minetest.log("action", "Sheriff <"..sheriffname.."> jailed player <"..playername..">.");
                        stonemakelight.candidate_by_name[sheriffname].action_delay = stonemakelight.candidate_by_name[sheriffname].action_delay + 1;
                    else
                        minetest.chat_send_player(sheriffname, "Player <"..playername.."> not online.");
                    end
				else
					minetest.chat_send_player(sheriffname, "There is small delay for jailing players, just in case.");
				end
			else
				minetest.chat_send_player(sheriffname, "You need to be sheriff with at least"..(stonemakelight.vote_needed*2).." votes.");
			end
		end
	end,
})

minetest.register_chatcommand("sheriffs", {
	params = "",
	description = "List all sheriff names.",
	func = function(playername)
        for key, val in pairs(stonemakelight.candidate_by_name) do
            if val.votes >= stonemakelight.vote_needed*3 then
                minetest.chat_send_player(playername, "Sheriff ***"..key.."***");
            elseif val.votes >= stonemakelight.vote_needed*2 then
                minetest.chat_send_player(playername, "Sheriff **"..key.."**");
            elseif val.votes >= stonemakelight.vote_needed then
                minetest.chat_send_player(playername, "Sheriff *"..key.."*");
            elseif val.votes < -stonemakelight.vote_needed then
                minetest.chat_send_player(playername, "Outlaw -"..key.."-");
            end
        end
	end,
})

--clear action delays
stonemakelight.vote = function()
	
	for key, val in pairs(stonemakelight.candidate_by_name) do
		val.action_delay = 0;
	end
	minetest.after(15, function()
        stonemakelight.vote();
	end)
end
stonemakelight.vote();
