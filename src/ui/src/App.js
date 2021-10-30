import './App.css';
import React, { useState } from 'react';

function App() {
  const [data, setData] = useState('');
  const [results, setResults] = useState([]);

  const handleChange = (e) => {
    setData(e.target.value)
  }

  const handleClick = async () => {
    const body = data;
    setData("");
    await fetch("/write", {
      method: "POST",
      body
    });
    const response = await fetch("/read");
    const array = await response.json();
    setResults(array);
  }

  return (
    <div className="App">
      <span>Enter some text to save:</span>
      <input type="text" value={data} onChange={handleChange} />
      <button type="button" onClick={handleClick}>Save</button>
      <br />
      <ul>
        {results.map(result => <li>{result}</li>)}
      </ul>
    </div >
  );
}

export default App;
