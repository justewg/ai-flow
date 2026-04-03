"use strict";

function sortByUpdatedAtDescending(items) {
  return [...items].sort((left, right) => String(right.updatedAt || "").localeCompare(String(left.updatedAt || "")));
}

function waitingSlice(taskState, task) {
  const waiting = taskState.meta && taskState.meta.waiting ? taskState.meta.waiting : {};
  return {
    taskId: taskState.taskId,
    issueNumber: task && Number.isInteger(task.issueNumber) ? task.issueNumber : null,
    waitCommentId: waiting.waitCommentId || taskState.canonicalWaitCommentId || null,
    kind: waiting.kind || null,
    commentUrl: waiting.commentUrl || null,
    pendingPost: waiting.pendingPost === true,
    waitingSince: waiting.waitingSince || null,
    updatedAt: taskState.updatedAt || null,
  };
}

async function derivePrimaryContexts(store) {
  const [tasks, taskStates] = await Promise.all([store.listTasks(), store.listTaskStates()]);
  const taskById = new Map(tasks.map((task) => [task.id, task]));

  const active = sortByUpdatedAtDescending(taskStates)
    .filter((taskState) => taskState.phase === "claimed" || taskState.phase === "executing")
    .map((taskState) => {
      const task = taskById.get(taskState.taskId) || null;
      const claim = taskState.meta && taskState.meta.claim ? taskState.meta.claim : {};
      return {
        taskId: taskState.taskId,
        issueNumber: task && Number.isInteger(task.issueNumber) ? task.issueNumber : null,
        itemId: claim.itemId || null,
        claimState: taskState.phase === "claimed" ? "claimed" : "executing",
        claimedAt: claim.claimedAt || null,
        activeExecutionId: taskState.activeExecutionId || null,
        updatedAt: taskState.updatedAt || null,
      };
    });

  const review = sortByUpdatedAtDescending(taskStates)
    .filter((taskState) => taskState.phase === "reviewing")
    .map((taskState) => {
      const task = taskById.get(taskState.taskId) || null;
      const reviewFeedback = taskState.meta && taskState.meta.reviewFeedback ? taskState.meta.reviewFeedback : {};
      return {
        taskId: taskState.taskId,
        issueNumber: task && Number.isInteger(task.issueNumber) ? task.issueNumber : null,
        prNumber: Number.isInteger(taskState.canonicalReviewPrNumber) ? taskState.canonicalReviewPrNumber : null,
        waitCommentId: taskState.canonicalWaitCommentId || null,
        commentUrl: reviewFeedback.commentUrl || null,
        pendingPost: reviewFeedback.pendingPost === true,
        waitingSince: reviewFeedback.waitingSince || null,
        updatedAt: taskState.updatedAt || null,
      };
    });

  const waiting = sortByUpdatedAtDescending(taskStates)
    .filter((taskState) => taskState.phase === "waiting_human")
    .map((taskState) => {
      const task = taskById.get(taskState.taskId) || null;
      return waitingSlice(taskState, task);
    });

  return {
    active,
    review,
    waiting,
  };
}

module.exports = {
  derivePrimaryContexts,
};
