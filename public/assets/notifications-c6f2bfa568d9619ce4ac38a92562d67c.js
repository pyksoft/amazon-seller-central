document.write('<link rel="stylesheet" type="text/css" href="/notifications.css">');

function addNotification(type,text) {
    var div = document.createElement('div');
    div.innerHTML = text;
    div.className += type +  'note-notification test';
    document.getElementsByClassName('flashes')[0].appendChild(div);
    setInterval(function () {
        div.remove();
    }, 5500);
}
;
