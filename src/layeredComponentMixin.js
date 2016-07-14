// Original code at https://github.com/Khan/react-components
// Some modifications were made to make it play nicely with NW.js

/*
 * The MIT License (MIT)
 *
 * Copyright (c) 2014 Khan Academy
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

/* Create a new "layer" on the page, like a modal or overlay.
 *
 * var LayeredComponent = React.createClass({
 *	 mixins: [LayeredComponentMixin],
 *	 render: function() {
 *		 // render like usual
 *	 },
 *	 renderLayer: function() {
 *		 // render a separate layer (the modal or overlay)
 *	 }
 * });
 */

Assert = require('assert');

module.exports = {
	load: function (win) {
		// Explicitly access all page globals via the window object
		// (required for NW.js compatibility)
		var React = win.React;
		var ReactDOM = win.ReactDOM;

		var document = win.document;

		var LayeredComponentMixin = {
			componentDidMount: function() {
				// Appending to the body is easier than managing the z-index of
				// everything on the page.  It's also better for accessibility and
				// makes stacking a snap (since components will stack in mount order).
				this._layer = document.createElement('div');
				document.body.appendChild(this._layer);
				this._renderLayer();
			},

			componentDidUpdate: function() {
				this._renderLayer();
			},

			componentWillUnmount: function() {
				this._unrenderLayer();
				document.body.removeChild(this._layer);
			},

			_renderLayer: function() {
				// By calling this method in componentDidMount() and
				// componentDidUpdate(), you're effectively creating a "wormhole" that
				// funnels React's hierarchical updates through to a DOM node on an
				// entirely different part of the page.
				Assert(this.renderLayer, "missing this.renderLayer() in component");

				var layerElement = this.renderLayer();
				// Renders can return null, but R.render() doesn't like being asked
				// to render null. If we get null back from renderLayer(), just render
				// a noscript element, like React does when an element's render returns
				// null.
				if (layerElement === null) {
					ReactDOM.render(React.createElement("noscript", null), this._layer);
				} else {
					ReactDOM.render(layerElement, this._layer);
				}

				if (this.layerDidMount) {
					this.layerDidMount(this._layer);
				}
			},

			_unrenderLayer: function() {
				if (this.layerWillUnmount) {
					this.layerWillUnmount(this._layer);
				}

				ReactDOM.unmountComponentAtNode(this._layer);
			}
		};

		return LayeredComponentMixin;
	},
};
