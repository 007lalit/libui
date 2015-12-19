// 9 september 2015
#import "uipriv_darwin.h"

@interface areaView : NSView {
	uiArea *libui_a;
}
- (id)initWithFrame:(NSRect)r area:(uiArea *)a;
- (uiModifiers)parseModifiers:(NSEvent *)e;
- (void)doMouseEvent:(NSEvent *)e;
- (int)sendKeyEvent:(uiAreaKeyEvent *)ke;
- (int)doKeyDownUp:(NSEvent *)e up:(int)up;
- (int)doKeyDown:(NSEvent *)e;
- (int)doKeyUp:(NSEvent *)e;
- (int)doFlagsChanged:(NSEvent *)e;
@end

struct uiArea {
	uiDarwinControl c;
	areaView *view;
	uiAreaHandler *ah;
};

uiDarwinDefineControl(
	uiArea,								// type name
	uiAreaType,							// type function
	view									// handle
)

@implementation areaView

- (id)initWithFrame:(NSRect)r area:(uiArea *)a
{
	self = [super initWithFrame:r];
	if (self)
		self->libui_a = a;
	return self;
}

- (void)drawRect:(NSRect)r
{
	CGContextRef c;
	uiAreaDrawParams dp;
	areaView *av;

	c = (CGContextRef) [[NSGraphicsContext currentContext] graphicsPort];
	dp.Context = newContext(c);

	// TODO frame or bounds?
	dp.ClientWidth = [self frame].size.width;
	dp.ClientHeight = [self frame].size.height;

	dp.ClipX = r.origin.x;
	dp.ClipY = r.origin.y;
	dp.ClipWidth = r.size.width;
	dp.ClipHeight = r.size.height;

	av = (areaView *) [self superview];
	dp.HScrollPos = [av hscrollPos];
	dp.VScrollPos = [av vscrollPos];

	// no need to save or restore the graphics state to reset transformations; Cocoa creates a brand-new context each time
	(*(self->libui_a->ah->Draw))(self->libui_a->ah, self->libui_a, &dp);

	freeContext(dp.Context);
}

- (BOOL)isFlipped
{
	return YES;
}

- (BOOL)acceptsFirstResponder
{
	return YES;
}

- (uiModifiers)parseModifiers:(NSEvent *)e
{
	NSEventModifierFlags mods;
	uiModifiers m;

	m = 0;
	mods = [e modifierFlags];
	if ((mods & NSControlKeyMask) != 0)
		m |= uiModifierCtrl;
	if ((mods & NSAlternateKeyMask) != 0)
		m |= uiModifierAlt;
	if ((mods & NSShiftKeyMask) != 0)
		m |= uiModifierShift;
	if ((mods & NSCommandKeyMask) != 0)
		m |= uiModifierSuper;
	return m;
}

// capture on drag is done automatically on OS X
- (void)doMouseEvent:(NSEvent *)e
{
	uiAreaMouseEvent me;
	NSPoint point;
	areaView *av;
	uintmax_t buttonNumber;
	NSUInteger pmb;
	unsigned int i, max;

	av = (areaView *) [self superview];

	// this will convert point to drawing space
	// thanks swillits in irc.freenode.net/#macdev
	point = [self convertPoint:[e locationInWindow] fromView:nil];
	me.X = point.x;
	me.Y = point.y;

	// TODO frame or bounds?
	me.ClientWidth = [self frame].size.width;
	me.ClientHeight = [self frame].size.height;
	me.HScrollPos = [av hscrollPos];
	me.VScrollPos = [av vscrollPos];

	buttonNumber = [e buttonNumber] + 1;
	// swap button numbers 2 and 3 (right and middle)
	if (buttonNumber == 2)
		buttonNumber = 3;
	else if (buttonNumber == 3)
		buttonNumber = 2;

	me.Down = 0;
	me.Up = 0;
	me.Count = 0;
	switch ([e type]) {
	case NSLeftMouseDown:
	case NSRightMouseDown:
	case NSOtherMouseDown:
		me.Down = buttonNumber;
		me.Count = [e clickCount];
		break;
	case NSLeftMouseUp:
	case NSRightMouseUp:
	case NSOtherMouseUp:
		me.Up = buttonNumber;
		break;
	case NSLeftMouseDragged:
	case NSRightMouseDragged:
	case NSOtherMouseDragged:
		// we include the button that triggered the dragged event in the Held fields
		buttonNumber = 0;
		break;
	}

	me.Modifiers = [self parseModifiers:e];

	pmb = [NSEvent pressedMouseButtons];
	me.Held1To64 = 0;
	if (buttonNumber != 1 && (pmb & 1) != 0)
		me.Held1To64 |= 1;
	if (buttonNumber != 2 && (pmb & 4) != 0)
		me.Held1To64 |= 2;
	if (buttonNumber != 3 && (pmb & 2) != 0)
		me.Held1To64 |= 4;
	// buttons 4..64
	max = 32;
	// TODO are the upper 32 bits just mirrored?
//	if (sizeof (NSUInteger) == 8)
//		max = 64;
	for (i = 4; i <= max; i++) {
		uint64_t j;

		if (buttonNumber == i)
			continue;
		j = 1 << (i - 1);
		if ((pmb & j) != 0)
			me.Held1To64 |= j;
	}

	(*(self->libui_a->ah->MouseEvent))(self->libui_a->ah, self->libui_a, &me);
}

#define mouseEvent(name) \
	- (void)name:(NSEvent *)e \
	{ \
		[self doMouseEvent:e]; \
	}
// TODO set up tracking events
mouseEvent(mouseMoved)
mouseEvent(mouseDragged)
mouseEvent(rightMouseDragged)
mouseEvent(otherMouseDragged)
mouseEvent(mouseDown)
mouseEvent(rightMouseDown)
mouseEvent(otherMouseDown)
mouseEvent(mouseUp)
mouseEvent(rightMouseUp)
mouseEvent(otherMouseUp)

// note: there is no equivalent to WM_CAPTURECHANGED on Mac OS X; there literally is no way to break a grab like that
// even if I invoke the task switcher and switch processes, the mouse grab will still be held until I let go of all buttons
// therefore, no DragBroken()

- (int)sendKeyEvent:(uiAreaKeyEvent *)ke
{
	return (*(self->libui_a->ah->KeyEvent))(self->libui_a->ah, self->libui_a, ke);
}

- (int)doKeyDownUp:(NSEvent *)e up:(int)up
{
	uiAreaKeyEvent ke;

	ke.Key = 0;
	ke.ExtKey = 0;
	ke.Modifier = 0;

	ke.Modifiers = [self parseModifiers:e];

	ke.Up = up;

	if (!fromKeycode([e keyCode], &ke))
		return 0;
	return [self sendKeyEvent:&ke];
}

- (int)doKeyDown:(NSEvent *)e
{
	return [self doKeyDownUp:e up:0];
}

- (int)doKeyUp:(NSEvent *)e
{
	return [self doKeyDownUp:e up:1];
}

- (int)doFlagsChanged:(NSEvent *)e
{
	uiAreaKeyEvent ke;
	uiModifiers whichmod;

	ke.Key = 0;
	ke.ExtKey = 0;

	// Mac OS X sends this event on both key up and key down.
	// Fortunately -[e keyCode] IS valid here, so we can simply map from key code to Modifiers, get the value of [e modifierFlags], and check if the respective bit is set or not — that will give us the up/down state
	if (!keycodeModifier([e keyCode], &whichmod))
		return 0;
	ke.Modifier = whichmod;
	ke.Modifiers = [self parseModifiers:e];
	ke.Up = (ke.Modifiers & ke.Modifier) == 0;
	// and then drop the current modifier from Modifiers
	ke.Modifiers &= ~ke.Modifier;
	return [self sendKeyEvent:&ke];
}

@end

// called by subclasses of -[NSApplication sendEvent:]
// by default, NSApplication eats some key events
// this prevents that from happening with uiArea
// see http://stackoverflow.com/questions/24099063/how-do-i-detect-keyup-in-my-nsview-with-the-command-key-held and http://lists.apple.com/archives/cocoa-dev/2003/Oct/msg00442.html
int sendAreaEvents(NSEvent *e)
{
	NSEventType type;
	id focused;
	areaView *view;

	type = [e type];
	if (type != NSKeyDown && type != NSKeyUp && type != NSFlagsChanged)
		return 0;
	focused = [[e window] firstResponder];
	if (focused == nil)
		return 0;
	if (![focused isKindOfClass:[areaView class]])
		return 0;
	view = (areaView *) focused;
	switch (type) {
	case NSKeyDown:
		return [view doKeyDown:e];
	case NSKeyUp:
		return [view doKeyUp:e];
	case NSFlagsChanged:
		return [view doFlagsChanged:e];
	}
	return 0;
}

// TODO
#if 0
	// we must redraw everything on resize because Windows requires it
	[self setNeedsDisplay:YES];
#endif

void uiAreaUpdateScroll(uiArea *a)
{
/* TODO
	NSRect frame;

	frame.origin = NSMakePoint(0, 0);
	frame.size.width = (*(a->ah->HScrollMax))(a->ah, a);
	frame.size.height = (*(a->ah->VScrollMax))(a->ah, a);
	[a->documentView setFrame:frame];
*/
}

void uiAreaQueueRedrawAll(uiArea *a)
{
	[a->view setNeedsDisplay:YES];
}

uiArea *uiNewArea(uiAreaHandler *ah)
{
	uiArea *a;

	a = (uiArea *) uiNewControl(uiAreaType());

	a->ah = ah;

	a->view = [[areaView alloc] initWithFrame:NSZeroRect area:a];

	uiDarwinFinishNewControl(a, uiArea);

	return a;
}
