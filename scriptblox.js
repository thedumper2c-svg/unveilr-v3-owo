fetch("https://scriptblox.com/api/script/fetch") // 20 most recent scripts. Also known as home page scripts.
    .then((res) => res.json())
    .then((data) => {
        for (const script of data.result.scripts) {
            const url = `https://scriptblox.com/script/${script.slug}`
            const rawscriptsUrl = script.script.match(/(https:\/\/rawscripts.net\/raw\/.+)"/)[1]
            if (!rawscriptsUrl) continue

            fetch(rawscriptsUrl).then(
                (data) => data.text()
                .then((content) => {
                    dumpInner(content, {
                        url: url
                    })
                })
            )
        }
    })
    .catch();