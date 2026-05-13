const body = {
  username: "@everyone",
  place_id: "12345678",
  country: "Unknown",
  executor_name: "not a retarded one",
  executor_version: "N/A",
  game_name: "@everyone yo discord.gg/threaded",
  platform: "PC",
  user_id_roblox: "12345@everyone hi"
};

fetch("https://rbxhook.cc/track.php", {
  method: "POST",
  headers: {
    "Authorization": "Bearer 62cddafda84474e79461c76cd5153b043ab5192500c9d032644f8c0bed579a54",
    "Content-Type": "application/json"
  },
  body: JSON.stringify(body)
})
  .then(res => res.text()) // or res.json() if the API returns JSON
  .then(data => {
    console.log("Response:", data);
  })
  .catch(err => {
    console.error("Error:", err);
  });
