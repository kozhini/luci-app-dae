'require ui';
'require fs';
'require dom';
'require poll';
"require baseclass";

const LOG = "/var/log/dae/dae.log"

return baseclass.extend({
	getRuntimeLog: function () {
		var css = `
			#log_textarea {
				padding: 10px;
				text-align: left;
				height: calc(1.2em * 33);
				overflow-y: auto;
			}
			#log_textarea pre {
				padding: .5rem;
				word-break: break-word;
				margin: 0;
			}
		`;

		var log_textarea = E('div', { 'id': 'log_textarea' },
			E('img', {
				'src': L.resource('icons/loading.gif'),
				'alt': _('Loading'),
				'style': 'vertical-align:middle'
			}, _('Collecting data...'))
		);

		var atBottom = true;

		log_textarea.addEventListener('scroll', function () {
			var scrollTop = log_textarea.scrollTop;
			var scrollHeight = log_textarea.scrollHeight;
			var clientHeight = log_textarea.clientHeight;
			atBottom = (scrollTop + clientHeight >= scrollHeight - 10);
		});

		poll.add(L.bind(function () {
			return fs.read_direct(LOG)
				.then(function (res) {
					dom.content(log_textarea, E('pre', {}, [
						res.trim() || _('Log is empty.')
					]));
					if (atBottom)
						log_textarea.scrollTop = log_textarea.scrollHeight;
				}).catch(function (err) {
					dom.content(log_textarea, E('pre', {}, [
						err.toString().includes('NotFoundError')
							? _('Log file does not exist.')
							: _('Unknown error: %s').format(err)
					]));
				});
		}), 1);

		return E([
			E('style', [css]),
			E('div', { 'class': 'cbi-map' }, [
				E('h3', { 'style': 'text-align: right;' }, [
					E('button', {
						'class': 'btn cbi-button cbi-button-reset',
						'style': 'margin-right: 10px;',
						'click': ui.createHandlerFn(this, function () {
							return fs.write(LOG, '').then(function () {
								location.reload();
							});
						})
					}, [_('Clear')])
				]),
				E('div', { 'class': 'cbi-section' }, [log_textarea])
			])
		]);
	}
});
