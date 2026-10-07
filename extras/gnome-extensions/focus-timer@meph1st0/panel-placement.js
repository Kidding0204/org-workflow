export function addToLeftPanel(panel, defaultLeftItems, role, indicator) {
    let position = defaultLeftItems.length;
    for (const extraRole of ['apps-menu', 'places-menu']) {
        if (extraRole in panel.statusArea)
            position++;
    }
    panel.addToStatusArea(role, indicator, position, 'left');
}

export function orderedPanelActors({
    dailyGroup,
    taskLabel,
    accessoryGroup,
}) {
    return [dailyGroup, taskLabel, accessoryGroup];
}

// Tray extensions can insert at position zero after us during session startup.
export function keepFirstInRightPanel(panel, indicator) {
    const box = panel._rightBox;
    const container = indicator.container;
    const place = () => {
        if (container.get_parent() === box && box.get_children()[0] !== container)
            box.set_child_at_index(container, 0);
    };
    const signal = box.connect('child-added', place);
    place();
    return () => box.disconnect(signal);
}
