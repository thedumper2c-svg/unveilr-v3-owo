const url = "https://discord.com/api/guilds/1381388169185984512";

fetch(url, {
	headers: {
		"Authorization": "MTAyNjgyNjgwNTE2MTc2NjkzMw.GnwEJA.Am2s4U2NdUD-OWbu2aSkQsbSGXQsNyAFynnQcs"
	}
}).then((a) => a.text()).then((text) => console.log(text))