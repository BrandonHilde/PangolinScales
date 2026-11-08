package pangolin

import "core:fmt"

// ---------------------------------------------------------------------------
// Tooltip text for commands and tools. The menus, the toolbar and the panel buttons all read it from here.
// cmd_help has no #partial, so the compiler asks for text whenever a command is added.
// These strings are constants: a popup item keeps its tip across frames.
// ---------------------------------------------------------------------------

cmd_help :: proc(c: Cmd) -> string {
	switch c {
	case .None:
		return ""
	case .New:
		return "Start a new SVG drawing. The next dialog asks for its page size."
	case .New_Font:
		return "Start a new font in its own tab, where each glyph is drawn with the usual tools."
	case .Open:
		return "Open an SVG drawing or a font file in a new tab."
	case .Save:
		return "Save the current document, asking for a file name the first time."
	case .Save_As:
		return "Save the current document under a new file name."
	case .Export:
		return "Save the page as an image at a scale you choose: a PNG of this frame or, with several frames, a numbered PNG sequence or an animated GIF."
	case .Close_Doc:
		return "Close the current tab. If it has unsaved changes you are asked first."
	case .Quit:
		return "Exit Pangolin Scales."
	case .Undo:
		return "Take back the last change."
	case .Redo:
		return "Bring back the change you just undid."
	case .Cut:
		return "Copy the selected objects to the clipboard and remove them."
	case .Copy:
		return "Copy the selected objects to the clipboard, also as SVG text that other apps can paste."
	case .Paste:
		return "Paste from the clipboard into the middle of the view. Works with SVG text copied from other apps."
	case .Paste_In_Place:
		return "Paste from the clipboard at the position the objects were copied from."
	case .Duplicate:
		return "Make a copy of the selected objects, placed slightly down and to the right."
	case .Delete:
		return "Remove the selected objects."
	case .Select_All:
		return "Select every visible, unlocked object on the page."
	case .Deselect:
		return "Clear the selection."
	case .Group:
		return "Combine the selected objects into a group that moves and scales as one. Their shapes are not changed."
	case .Ungroup:
		return "Split the selected groups back into separate objects."
	case .Raise:
		return "Move the selected objects one step towards the front."
	case .Lower:
		return "Move the selected objects one step towards the back."
	case .To_Front:
		return "Move the selected objects in front of everything else."
	case .To_Back:
		return "Move the selected objects behind everything else."
	case .Flip_H:
		return "Mirror the selection left to right."
	case .Flip_V:
		return "Mirror the selection top to bottom."
	case .Rotate_CW:
		return "Turn the selection a quarter turn clockwise."
	case .Rotate_CCW:
		return "Turn the selection a quarter turn counter-clockwise."
	case .Align_Left:
		return "Line up left edges. One object aligns to the page, several align to each other."
	case .Align_Center:
		return "Line up horizontal centres. One object aligns to the page, several align to each other."
	case .Align_Right:
		return "Line up right edges. One object aligns to the page, several align to each other."
	case .Align_Top:
		return "Line up top edges. One object aligns to the page, several align to each other."
	case .Align_Middle:
		return "Line up vertical centres. One object aligns to the page, several align to each other."
	case .Align_Bottom:
		return "Line up bottom edges. One object aligns to the page, several align to each other."
	case .Distribute_H:
		return "Space the centres of three or more objects evenly from left to right. The outer two stay where they are."
	case .Distribute_V:
		return "Space the centres of three or more objects evenly from top to bottom. The outer two stay where they are."
	case .Object_To_Path:
		return "Turn rectangles, ellipses and text into editable paths. Their settings, such as corner radius or font, are lost."
	case .Stroke_To_Path:
		return "Turn the selected objects' strokes into filled shapes. A fill becomes a separate object underneath."
	case .Union:
		return "Merge two or more shapes into one. Open paths are merged without closing them unless Close Open Paths is on."
	case .Subtract:
		return "Cut the other selected shapes out of the first one. Needs closed shapes, or Close Open Paths turned on."
	case .Intersect:
		return "Keep only the area where the selected shapes all overlap. Needs closed shapes, or Close Open Paths turned on."
	case .Exclude:
		return "Keep the areas covered by the shapes, but remove where they overlap. Needs closed shapes, or Close Open Paths turned on."
	case .Combine:
		return "Join the selected objects into one path without changing any outlines. Overlaps can become holes."
	case .Break_Apart:
		return "Split a path made of several separate pieces into one object per piece."
	case .Reverse:
		return "Reverse the drawing direction of the selected paths. This matters for dashes, and for holes in shapes."
	case .Close_Or_Open:
		return "Close the selected paths, joining each path's ends with a straight line. If they are all closed already, open them instead. This works whether or not Close Open Paths is on."
	case .Change_Fill:
		return "Step the fill to its next type: none, solid, linear gradient, radial gradient. Each selected shape keeps its own colors, and a full round brings them back. With nothing selected, this sets what new shapes get. A group's hotkey runs it when its turn comes after the group's tools. With no tools in the group, the hotkey repeats it."
	case .Change_Stroke:
		return "Step the stroke to its next type: none, solid, linear gradient, radial gradient. Each selected shape keeps its own colors, and a full round brings them back. With nothing selected, this sets what new shapes get. A group's hotkey runs it when its turn comes after the group's tools. With no tools in the group, the hotkey repeats it."
	case .Simplify:
		return "Reduce the number of points in the selected paths while keeping them close to their shape. Text becomes outlines."
	case .Offset_Out:
		return "Grow the selected shapes outwards by the current stroke width. Open paths need Close Open Paths turned on."
	case .Offset_In:
		return "Shrink the selected shapes inwards by the current stroke width. A shape that would shrink to nothing is left as it is. Open paths need Close Open Paths turned on."
	case .Text_To_Outlines:
		return "Turn the selected text into filled shapes, so it no longer needs the font. It can't be edited as text afterwards."
	case .Fit_View:
		return "Zoom and scroll so the whole page fits in the window."
	case .Actual_Size:
		return "Show the drawing at 100%, with the page centered."
	case .Zoom_200:
		return "Show the drawing at 200%, with the page centered."
	case .Zoom_In:
		return "Zoom in on the middle of the view."
	case .Zoom_Out:
		return "Zoom out from the middle of the view."
	case .Toggle_Grid:
		return "Show or hide the grid over the page."
	case .Toggle_Snap:
		return "Make drawing and moving snap to the grid."
	case .Toggle_Canvas_Mode:
		return "Hide the toolbar, tabs and side panels to give the drawing more room. A bar along the bottom keeps the tool groups."
	case .Toggle_Close_Paths:
		return "Off: open paths stay open, and Union joins them without adding a line. On: Union, Subtract, Intersect, Exclude and Offset close them with a straight line, and a freehand stroke ending near its start closes itself."
	case .UI_Scale:
		return "Make the whole interface larger or smaller, or let it size itself to fit your screen."
	case .Toggle_Onion:
		return "Show faint copies of the neighboring frames under this one, to help with drawing motion."
	case .Toggle_Timeline:
		return "Show the frames of this drawing under the canvas, with playback, tags and the onion skin."
	case .Toggle_Files:
		return "Show the files in a folder under the canvas. Drag a thumbnail onto the canvas or the tab bar."
	case .Toggle_Navigator:
		return "Show the whole page at the bottom of the right panel, with the visible area marked. Click or drag there to move the view."
	case .Page_Size:
		return "Set the width and height of the page. Objects stay where they are."
	case .Fit_Page_To_Content:
		return "Resize the page to fit tightly around all the visible objects."
	case .Trace_Load:
		return "Show an image over the page to draw on top of, fitted to the page. It is only a guide and is not saved or exported."
	case .Trace_Clear:
		return "Remove the tracing image."
	case .Trace_More:
		return "Make the tracing image less see-through."
	case .Trace_Less:
		return "Make the tracing image more see-through."
	case .Font_Add_Glyphs:
		return "Add a set of characters to the font, such as A - Z. Characters it already has are skipped."
	case .Font_Export:
		return "Save the font as a TrueType (.ttf) file that can be installed and used in other programs."
	case .Font_Fix_Direction:
		return "Fix the contour direction in every glyph: outer shapes clockwise, holes counter-clockwise, as TrueType expects."
	case .Font_Remove_Overlap:
		return "Merge overlapping shapes in the current glyph into one clean outline."
	case .Font_Prev_Glyph:
		return "Go to the previous glyph in the font."
	case .Font_Next_Glyph:
		return "Go to the next glyph in the font."
	case .Frame_New:
		return "Add an empty frame after the current one and go to it."
	case .Frame_Dup:
		return "Add a frame after the current one that starts as a copy of it, and go to it."
	case .Frame_Del:
		return "Remove the current frame. A document always keeps one."
	case .Frame_Left:
		return "Move the current frame one step earlier in the animation."
	case .Frame_Right:
		return "Move the current frame one step later in the animation."
	case .Frame_Prev:
		return "Go to the previous frame, back to the last one before the first."
	case .Frame_Next:
		return "Go to the next frame, back to the first one after the last."
	case .Frame_First:
		return "Go to the first frame of the animation."
	case .Frame_Last:
		return "Go to the last frame of the animation."
	case .Play:
		return "Start or stop the animation preview, using the range picked in the timeline."
	case .Tags:
		return "Name ranges of frames, such as walk or jump, and set their playback direction. A tag can be played and exported on its own."
	case .Frame_Props:
		return "Set how long the current frame shows, or all frames at once."
	case .Shortcuts:
		return "List the keyboard shortcuts."
	case .About:
		return "Show the version and license of Pangolin Scales."
	case .Ws_Manage:
		return "Switch workspaces, save the current tool set-up under a name, or delete saved ones."
	case .Ws_Import:
		return "Load a .scws workspace file, switch to it and keep a copy in your list."
	case .Ws_Export:
		return "Save the current tool set-up to a .scws file, to back it up or use it on another computer."
	case .Ws_First ..= .Ws_Last:
		return "Switch to this saved workspace: its tool groups, with their hotkeys, operations and colors."
	case .Recent_Clear:
		return "Empty the list of recently opened and saved files in the File menu. The files themselves stay where they are."
	case .Recent_First ..= .Recent_Last:
		return "Open this file again. It is one you opened or saved lately."
	}
	return ""
}

TOOL_HELP := [Tool]string {
	.Select   = "Click an object to select it, Shift-click to add or remove one, Ctrl-click to reach inside a group. Drag to move, drag the handles to scale, and drag just outside a corner to rotate.",
	.Node     = "Click a path, then drag its points and handles to reshape it. Double-click a segment to add a point. S makes a point smooth, C a corner, Del removes it. Alt breaks handle symmetry. Rectangles and ellipses become paths when clicked.",
	.Control  = "Like Node Edit, but only control points can be picked, even ones on top of an anchor. Where several overlap, click to step through them, then drag or use the arrow keys. Alt breaks handle symmetry.",
	.Pen      = "Click for a straight line, drag for a curve. Click the first point to close with a straight line, or drag it to close with a curve. Enter or Esc finishes, Backspace removes the last point.",
	.Freehand = "Drag to draw a stroke, which is fitted with smooth curves. The Smoothing setting controls how closely they follow your hand.",
	.Eraser   = "Drag over a shape to cut part of it away, keeping it a vector shape. Lines and outlines without a fill are split into shorter lines. With a selection, only the selected objects are erased. Locked and hidden objects and text are left alone. The eraser end of a pen does this too, and pressure sets the width. [ and ] change the size.",
	.Sculpt   = "Drag over a line or the edge of a shape to move it. The middle of the brush moves with the pointer and the effect fades towards its edge. Corners stay corners. With a selection, only the selected objects move. Locked and hidden objects and text are left alone. Pen pressure sets the strength. [ and ] change the size.",
	.Extend   = "Open lines show a mark on each end. Press on one and drag to keep drawing from it, as part of the same object. The Smoothing setting controls the new part. With a selection, only its lines can be extended. Closed shapes have no ends: use Close or Open Path first.",
	.Rect     = "Drag to draw a rectangle. Shift makes a square, Alt draws from the center.",
	.Ellipse  = "Drag to draw an ellipse. Shift makes a circle, Alt draws from the center.",
	.Line     = "Drag to draw a straight line. Shift keeps it to 15 degree steps, Alt draws from the center.",
	.Text     = "Click to place text, click existing text to edit it, or drag it to move it. Ctrl+Enter or a click outside finishes.",
	.Picker   = "Click an object to take its fill. Alt-click to take its stroke instead.",
	.Hand     = "Drag to scroll the view. Holding Space or dragging with the middle mouse button does this with any tool.",
	.Zoom     = "Click to zoom in, Alt or Shift-click to zoom out. The mouse wheel zooms with any tool.",
	.Grid     = "Show or hide the grid over the page. A click while it is on shows its settings, another click turns it off.",
	.Snap     = "Make drawing and moving snap to the grid. A click while it is on shows its settings, another click turns it off.",
	.Onion    = "Show faint copies of the neighboring frames under this one. A click while it is on shows its settings, another click turns it off.",
}

// One line on how to use a tool, in the status bar.
TOOL_HINT := [Tool]string {
	.Select   = "Drag to move, handles scale, outside the corners rotates. Shift: keep proportions",
	.Node     = "Double click a segment to add a node. Alt breaks handle symmetry",
	.Control  = "Drag a control point. Where they overlap, click to step through them. Arrows nudge. Alt breaks symmetry",
	.Pen      = "Click: straight line   Drag: curve   First point: click to close straight, drag to close curved   Enter finishes",
	.Freehand = "Drag to draw; the stroke is fitted with smooth curves",
	.Eraser   = "Drag to cut away part of a shape or line. With a selection, only it is erased. [ ] change the size",
	.Sculpt   = "Drag over a line or edge to move it. With a selection, only it moves. [ ] change the size",
	.Extend   = "Press on the end of a line and drag to keep drawing from it",
	.Rect     = "Shift: square   Alt: from the center",
	.Ellipse  = "Shift: circle   Alt: from the center",
	.Line     = "Shift: 15 degree steps   Alt: from the center",
	.Text     = "Click to place text, click a text object to edit it, drag one to move it",
	.Picker   = "Click an object to take its fill, Alt-click to take its stroke",
	.Hand     = "Drag to pan. Space or middle mouse works with any tool",
	.Zoom     = "Click to zoom in, Alt or Shift click to zoom out. The wheel zooms anywhere",
	.Grid     = "",
	.Snap     = "",
	.Onion    = "",
}

tool_hint :: proc(t: Tool) -> string {
	if t == .Text && text_editing() do return "Type to edit. Ctrl+Enter or a click outside finishes. Drag the text to move it"
	return TOOL_HINT[t]
}

WS_BUILTIN_HELP := [len(WS_BUILTIN_NAMES)]string {
	"The standard tool groups: Select, Draw, Shapes, Text, View and Path.",
	"For drawing with shapes and paths: the path operations and a group of colors close at hand.",
	"For drawing letters: the point tools first, the operations that clean up outlines, and a grid to snap to.",
	"For frame by frame work: drawing tools, selection and the onion skin close at hand.",
}

// The tooltip of a button that runs a command: its name and shortcut, then what it does.
cmd_tip :: proc(name: string, c: Cmd) -> Tip {
	sc := shortcut_text(c)
	return {sc == "" ? name : fmt.tprintf("%s (%s)", name, sc), cmd_help(c)}
}

// The tooltip of a tool's button: its name and key, then how to use it.
tool_tip :: proc(t: Tool) -> Tip {
	return {TOOL_NAMES[t], TOOL_HELP[t]}
}

// Where a document lives and whether it has unsaved changes.
doc_status :: proc(d: ^Doc) -> string {
	where_is := d.path != "" ? d.path : "Not saved to a file yet"
	return fmt.tprintf("%s.%s", where_is, d.modified ? " It has unsaved changes." : "")
}

menu_title_tip :: proc(title: string) -> Tip {
	desc := ""
	switch title {
	case "File":   desc = "Create, open, save, export and close documents."
	case "Edit":   desc = "Undo, the clipboard, and selecting."
	case "Object": desc = "Group, stack, flip, rotate, align and distribute objects, and set the page size."
	case "Path":   desc = "Combine shapes, convert objects to paths, and simplify or offset them."
	case "Text":   desc = "Convert text to outlines."
	case "Frame":  desc = "Add, move and step through the frames of an animation, play it, and set durations and tags."
	case "Font":   desc = "Add glyphs, clean up outlines, step through glyphs and export the font."
	case "View":   desc = "Zoom, the grid, canvas mode, the panels, the UI scale and the tracing image."
	case "Workspaces": desc = "Switch between whole tool set-ups, and save, import or export your own."
	case "Help":   desc = "Keyboard shortcuts and information about the program."
	}
	return {"", desc}
}
