const fs = require("fs");
const path = require("path");
const { validateSiteYaml } = require("./contentValidation");

const repoRoot = path.resolve(__dirname, "..", "..", "..");
const contentPath = process.argv[2]
  ? path.resolve(process.cwd(), process.argv[2])
  : path.join(repoRoot, "content", "site.yaml");

const yamlText = fs.readFileSync(contentPath, "utf8");
const validation = validateSiteYaml(yamlText);

if (validation.ok) {
  console.log(`Content validation passed: ${contentPath}`);
  if (validation.warnings.length > 0) {
    console.log("Warnings:");
    for (const warning of validation.warnings) console.log(`- ${warning}`);
  }
  process.exit(0);
}

console.error(`Content validation failed: ${contentPath}`);
for (const error of validation.errors) console.error(`- ${error}`);
if (validation.warnings.length > 0) {
  console.error("Warnings:");
  for (const warning of validation.warnings) console.error(`- ${warning}`);
}
process.exit(1);
