// Logical pixels. Preserve the task until the parent has shrunk to 80px.
export function titleLayout(available, fixed, taskNatural, parentNatural = 0) {
    const budget = Math.max(0, available - fixed);
    let task = Math.min(320, Math.max(0, taskNatural));
    let parent = Math.max(0, parentNatural);
    let excess = Math.max(0, task + parent - budget);
    const parentReduction = Math.min(excess, Math.max(0, parent - 80));
    parent -= parentReduction;
    excess -= parentReduction;
    const taskReduction = Math.min(excess, Math.max(0, task - 140));
    task -= taskReduction;
    excess -= taskReduction;
    parent -= Math.min(excess, parent);
    task = Math.min(task, Math.max(0, budget - parent));
    return {task: Math.floor(task), parent: Math.floor(parent)};
}
