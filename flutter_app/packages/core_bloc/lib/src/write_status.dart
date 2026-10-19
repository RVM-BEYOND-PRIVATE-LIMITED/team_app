/// Lifecycle of a one-shot write flow (create/update/delete/upload), shared by
/// every write bloc across the apps. Sibling to [LoadStatus] for read flows.
enum WriteStatus { idle, submitting, success, failure }
