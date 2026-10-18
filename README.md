# Desmaptic Catalog

[Desmaptic](https://desmaptic.com) turns the iPhone or iPad you already have into a deck of buttons for your Mac,
like a Stream Deck. This repository holds its **Gallery**: every ready-made widget, app page and scene
the Gallery offers, as the files the Desmaptic Agent uses.

The app and the agent are closed source; the catalog is published so that you can read what a button
will run on your Mac before you add it, find a template by searching GitHub, and point an AI assistant at
real examples.

## What is here

```
catalog.json        what the Gallery publishes, in order: widgets, shelves, preview (the widgets the app shows before it is paired),
                    categories, apps, scene collections
widgets/<id>/       one widget: item.json (the button template, its texts in five languages) and its files
apps/<id>/          one Mac app: app.json (its buttons and pages) and the scripts they call
scenes/<id>/        one whole-page scene: scene.json, the engine that draws every tile, its faces and cover
```

- `.json` — templates. Inside a long text, a line `@file:<path>` stands for that file, next to the template.
- `.zsh` — scripts the agent runs on your Mac: a tap or a long press runs the button's script once; a
  startup script runs while its button is on the deck and redraws a live face.
- `.svg` — button faces: what the button shows at rest, and a sample for the Gallery.
- `"permissions"` in a template — what macOS asks you to allow before the button works (Accessibility,
  Automation, Calendars and so on).

Scripts run as your user, started by the agent with a fixed environment. They talk to the agent only
through its local API at `127.0.0.1`, with the agent's local token (`$DESMAPTIC_TOKEN`; the agent makes a
new one each time it starts serving), and keep their state in `$DESMAPTIC_STORAGE`.

## Add a widget from the Gallery

You never copy files from here by hand.

1. When Desmaptic is out, install it on your iPhone or iPad and the Desmaptic Agent on your Mac, and
   pair them: https://desmaptic.com
2. On the phone, tap the Gallery button in the deck's toolbar.
3. Pick a widget, a page for one of your Mac's apps, or a scene, and tap **Add**.

The phone gets the catalog from your Mac's agent, so the Gallery always matches the agent you run, and a
page for an app shows only when that Mac has the app. The agent downloads each release of this repository
itself and installs it only when it carries the catalog's signature; a template that needs a newer agent
stays hidden until you update. A button you added is your own copy: edit it as
you like. A newer version of a template does not change a button you already have; to take it, add the
button or page again.

## Write your own widgets

- **With an AI assistant.** Connect Claude Code, Claude Desktop or Codex in the agent's window
  (AI Assistants), then ask for what you want: "a button that mutes Zoom", "a live CPU graph". The
  assistant gets the button format, the faces and the live-widget API from the agent, shows you the
  change, and the phone asks you to accept it.
- **By hand.** In the button editor on the phone: a keystroke, a shell command, an AppleScript, or a
  startup script that draws a live face.
- **From this catalog.** Every script here is a working example: start from the one closest to your idea.

Documentation: https://desmaptic.com/docs

## Report a problem

A script that does something it should not — see [SECURITY.md](SECURITY.md). Anything else — a template
that stopped working, a question or an idea — write to support@desmaptic.com.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

The catalog is source-available, free to use and modify: you may use the templates, change them and
share them, at home or at work, as long as the license and its notice go with them. You may not use them
in a product that competes with Desmaptic, such as another remote-control app or a paid set of the same
widgets. The terms: [PolyForm Shield 1.0.0](LICENSE).

The license gives no rights to the Desmaptic name or logo: do not use them in your own products.
