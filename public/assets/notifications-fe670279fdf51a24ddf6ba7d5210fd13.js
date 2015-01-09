function addNotification(text) {
    var div = document.createElement('div');
    div.innerHTML = text;
    div.className += 'note';
    document.getElementsByClassName('flashes').appendChild(div);
    setInterval(function () {
        div.remove();
    }, 5500);
}
;
