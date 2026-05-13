const Data = new FormData()
Data.append("file", "Hello")

const response = await fetch("https://aktheportal.helpso.me/predict", {
    method: "POST",
    headers: {
        "X-API-Key": "hellobat1asdj3982y297rfs"
    },
    body: Data
})

console.log(response)