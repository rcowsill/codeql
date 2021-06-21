import dateFns from 'date-fns';
import dateFnsFp from 'date-fns/fp';
import dateFnsEsm from 'date-fns/esm';
import moment from 'moment';
import dateformat from 'dateformat';

function main() {
    let time = new Date();
    let taint = decodeURIComponent(window.location.hash.substring(1));

    document.body.innerHTML = `Time is ${dateFns.format(time, taint)}`; // NOT OK
    document.body.innerHTML = `Time is ${dateFnsEsm.format(time, taint)}`; // NOT OK
    document.body.innerHTML = `Time is ${dateFnsFp.format(taint)(time)}`; // NOT OK
    document.body.innerHTML = `Time is ${dateFns.format(taint, time)}`; // OK - time arg is safe
    document.body.innerHTML = `Time is ${dateFnsFp.format(time)(taint)}`; // OK - time arg is safe
    document.body.innerHTML = `Time is ${moment(time).format(taint)}`; // NOT OK
    document.body.innerHTML = `Time is ${moment(taint).format()}`; // OK
    document.body.innerHTML = `Time is ${dateformat(time, taint)}`; // NOT OK

    import dayjs from 'dayjs';
    document.body.innerHTML = `Time is ${dayjs(time).format(taint)}`; // NOT OK
}

import LuxonAdapter from "@date-io/luxon";
import DateFnsAdapter from "@date-io/date-fns";
import MomentAdapter from "@date-io/moment";
import DayJSAdapter from "@date-io/dayjs"

function dateio() {
    let taint = decodeURIComponent(window.location.hash.substring(1));

    const dateFns = new DateFnsAdapter();
    const luxon = new LuxonAdapter();
    const moment = new MomentAdapter();
    const dayjs = new DayJSAdapter();

    document.body.innerHTML = `Time is ${dateFns.formatByString(new Date(), taint)}`; // NOT OK
    document.body.innerHTML = `Time is ${luxon.formatByString(luxon.date(), taint)}`; // NOT OK
    document.body.innerHTML = `Time is ${moment.formatByString(moment.date(), taint)}`; // NOT OK
    document.body.innerHTML = `Time is ${dayjs.formatByString(dayjs.date(), taint)}`; // NOT OK
}