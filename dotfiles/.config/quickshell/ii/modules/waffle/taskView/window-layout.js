function scaleWindow(hyprlandClient, maxWindowWidth, maxWindowHeight) {
    const fallbackWidth = Math.max(Number(maxWindowWidth) || 0, 1);
    const fallbackHeight = Math.max(Number(maxWindowHeight) || 0, 1);
    const size = hyprlandClient?.size ?? [];
    const width = Math.max(Number(size[0] ?? fallbackWidth) || fallbackWidth, 1);
    const height = Math.max(Number(size[1] ?? fallbackHeight) || fallbackHeight, 1);
    const [xScale, yScale] = [fallbackWidth / width, fallbackHeight / height];
    const scale = Math.min(xScale, yScale);
    return Qt.size(Math.max(width * scale, 1), Math.max(height * scale, 1))
}

function arrangedClients(hyprlandClients, maxRowWidth, maxWindowWidth, maxWindowHeight) {
    const count = hyprlandClients.length;
    const resultLayout = [];

    var i = 0;
    while (i < count) {
        var row = [];
        var rowWidth = 0;
        var j = i;

        while (j < count) {
            const client = hyprlandClients[j];
            const scaledSize = scaleWindow(client, maxWindowWidth, maxWindowHeight);

            if (rowWidth + scaledSize.width <= maxRowWidth || row.length === 0) {
                row.push(client);
                rowWidth += scaledSize.width;
                j++;
            } else {
                break;
            }
        }
        
        resultLayout.push(row);
        i = j;
    }

    return resultLayout;
}
