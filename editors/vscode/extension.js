const vscode = require('vscode');
const { LanguageClient, TransportKind } = require('vscode-languageclient/node');
let client;
function activate(context) {
  let serverOptions = {
    run: { command: "./ghostty-ls", transport: TransportKind.stdio },
  };
  let clientOptions = {
    documentSelector: [
      { scheme: "file", language: "ghostty" },

    ],
  };

  client = new LanguageClient(
    "ghostty-ls",
    "ghostty-ls",
    serverOptions,
    clientOptions
  );
  return client.start();
}
function deactivate() {
  if (!client || !client.needsStop) {
    return undefined;
  }
  return client.stop();
}
module.exports = {
  activate,
  deactivate
}
