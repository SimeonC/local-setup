import fs from "fs";
import path from "path";
import os from "os";

const fishDirPath = path.join(os.homedir(), ".config", "fish");
const functionsDirPath = path.join(fishDirPath, "functions");

const files = [path.join(fishDirPath, "config.fish")]
  .concat(
    fs
      .readdirSync(functionsDirPath)
      .filter(
        (filename) => filename.endsWith(".fish") && !filename.startsWith("_")
      )
      .map((filename) => path.join(functionsDirPath, filename))
  )
  .map((filename) => ({
    name: path.basename(filename),
    location: filename,
    arg: filename,
  }));

console.log(
  JSON.stringify({
    items: files.map(({ name, location, arg }) => ({
      uid: name,
      title: name,
      subtitle: location,
      arg,
      match: name.split(/[ .-_]/).join(" "),
    })),
  })
);
