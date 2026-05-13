// @ts-check
/** @param {number} size */
const calculate = (size) => {
    const kilobytes = size / 1024//Math.min(size / 1024, 1024)

    if(kilobytes < 10) return 0;

    // for 700 kilobytes, the timeout should be 20
    // for 100, the timeout should be like 4
    // for 50: 2

    const ratio = 27.5;
    const timeoutFloat = kilobytes / ratio

    return Math.min(timeoutFloat > 20 ? Math.floor(timeoutFloat) : Math.ceil(timeoutFloat), 40)
}
/**const sizes = [ 1, 8, 50, 100, 700 ]

for (let size of sizes) {
    console.log(`${size} kilobyte(s): ${calculate(size * 1024)}`)
}*/
module.exports = calculate 